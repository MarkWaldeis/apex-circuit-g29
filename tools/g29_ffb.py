"""Echtes Force Feedback fuer das Logitech G29/G920/G923 (DirectInput, ohne
Zusatzpakete).

Warum es dieses Programm gibt
-----------------------------
Godot 4 hat keine Force-Feedback-Schnittstelle, und diese Lenkraeder haben keine
Rumble-Motoren, auf die `Input.start_joy_vibration` wirken koennte. Das Spiel
kann die Kraft also nicht selbst erzeugen. Das Lenkrad haengt aber als
DirectInput-Geraet am PC, und DirectInput kann sehr wohl Kraftbefehle an das
Lenkrad schicken. Genau das macht dieses Programm: es liest die Fahrzeugwerte,
die das Spiel per UDP schickt, und uebersetzt sie in echte Kraefte am Lenkrad.

Gesucht wird die ganze Logitech-Familie der drei Raeder, die der Auftrag nennt:
**G29, G920, G923** (die G923 "TrueForce"-Zusatzkanaele brauchen wir nicht; sie
spielt die Standard-DirectInput-Effekte genau wie die anderen zwei). Wer ein
anderes Rad hat, gibt seinen Namen mit `--name` an.

Protokoll (vom Spiel gesendet, UTF-8 JSON, ein Objekt pro Paket):

    v2 (das Spiel):
    {"v":2,"torque":-0.42,"damper":0.29,"friction":0.14,"rumble":0.55,
     "rumble_hz":31.0,"pulse":0.0,"pulse_dir":0.0,"spring":0.0,"gain":1.0,
     "event":"kerb","speed":48.3,"source":"Kerb","clip":0.0,"damage":0.0}

    torque      -1.0 .. +1.0  Grundkraft, + = drueckt nach rechts. Die Staerke
                              aus dem Menue steckt hier schon drin; der Helfer
                              skaliert sie NICHT ein zweites Mal (frueher tat er
                              das: 75 % Einstellung kamen als 56 % am Rad an).
    damper       0.0 ..  1.0  geschwindigkeitsabhaengige Daempfung
    friction     0.0 ..  1.0  Reibung (Stand, Kerb, Kies, Gras)
    rumble       0.0 ..  1.0  Amplitude des Ruettelns
    rumble_hz    5.0 .. 60.0  Frequenz dazu (Kerb schnell, Kies grob)
    pulse        0.0 ..  1.0  einmaliger Stoss (Schalten, Aufprall); er sitzt
                              sofort auf der Kraft und klingt in 0,12 s ab
    pulse_dir   -1.0 .. +1.0  Richtung des Stosses (+ = rechts)
    spring       0.0 ..  1.0  Rest-Zentrierfeder, Standard 0 (das Zentrieren
                              macht der Nachlauf des Spiels)
    source/clip/damage        Herkunft der Kraft, Anteil "am Anschlag" und
                              Schaden - nur fuer Anzeige und Diagnose

    v1 (alte Sender, z.B. tools/ffb_send_test.py): "force", "damp", "fric".
    Beide Varianten werden gelesen, damit ein alter Sender den Helfer nicht
    lahmlegt.

Standardmaessig hoert das Programm auf 127.0.0.1:5601. Kommt 0,5 s lang kein
Paket (Spiel beendet, Menue), fallen die Kraefte zurueck, damit das Lenkrad
nicht gegen einen alten Befehl drueckt.

Aufrufe
-------
    python tools/g29_ffb.py                 # normaler Betrieb
    python tools/g29_ffb.py --selftest      # Geraet pruefen, Effekte laden, kurz Kraft geben
    python tools/g29_ffb.py --list          # zeigen, welche Lenkraeder DirectInput sieht
    python tools/g29_ffb.py --invert        # Kraftrichtung umdrehen
    python tools/g29_ffb.py --name G923     # anderes Rad als G29/G920/G923 suchen
    python tools/g29_ffb.py --dry-run       # Kette ohne Lenkrad: Pakete, Rampe, Grenzen
    python tools/g29_ffb.py --check        # Kette ohne Lenkrad PRUEFEN (Exit 0/1)
    python tools/g29_ffb.py --demo          # alle Fahrsituationen am echten Rad fuehlen
    python tools/g29_ffb.py --sign-check    # messen, wohin eine positive Kraft dreht

Das G29/G920/G923 braucht sein Netzteil: ohne Netzteil meldet es sich an,
liefert aber keine Achsendaten und kann auch keine Kraft erzeugen. `--selftest`
sagt das ausdruecklich, statt Erfolg vorzutaeuschen.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import socket
import sys
import threading
import time
from ctypes import wintypes

DWORD = wintypes.DWORD
LONG = ctypes.c_long
WORD = wintypes.WORD
HRESULT = ctypes.c_long

DIRECTINPUT_VERSION = 0x0800

DI8DEVCLASS_GAMECTRL = 4
DIEDFL_ATTACHEDONLY = 0x00000001

DISCL_BACKGROUND = 0x00000008
DISCL_EXCLUSIVE = 0x00000001
DISCL_NONEXCLUSIVE = 0x00000002

DIDF_ABSAXIS = 0x00000001

DIDFT_AXIS = 0x00000003
DIDFT_ABSAXIS = 0x00000001
DIDFT_ANYINSTANCE = 0x00FFFF00
DIDOI_ASPECTPOSITION = 0x00000100

DIEFF_OBJECTOFFSETS = 0x00000002
DIEFF_CARTESIAN = 0x00000010

DIEP_TYPESPECIFICPARAMS = 0x00000100
DIEP_START = 0x20000000

DIEB_NONE = 0xFFFFFFFF

DI_OK = 0
DIERR_UNSUPPORTED = -2147024846
DIERR_DEVICENOTREG = -2147221004
DIERR_ACQUIRED = -2147220992
DIERR_INPUTLOST = -2147220990
DIERR_NOTACQUIRED = -2147220989
DIERR_DEVICEFULL = -2147220994
DIERR_UNPLUGGED = -2147220996

MAX_PATH = 260

## --- Verhalten der Kraefte ---------------------------------------------------
## Ein Lenkrad ist keine Treppe. Das Spiel schickt 60 Pakete je Sekunde, der
## Helfer rechnet mit 200 Hz weiter: die Kraft wird zwischen den Paketen
## nachgezogen, statt in Stufen zu springen. Ein Schlag darf schnell kommen
## (Wand, Kerb, Schalten), das Nachlassen dauert etwas.
TORQUE_RISE = 40.0      ## Kraft pro Sekunde, wenn sie steigt (0.2/Sample bei 200 Hz)
TORQUE_FALL = 8.0       ## Kraft pro Sekunde, wenn sie faellt
PULSE_MIX = 0.70        ## wie stark ein Puls (Schalten, Aufprall) auf die Kraft geht
PULSE_DECAY = 0.12      ## s, bis ein Puls wieder weg ist
IDLE_SPRING = 0.0       ## Feder im Leerlauf: aus (das Zentrieren macht der Nachlauf)
ACK_PERIOD = 0.1        ## s zwischen zwei Lebenszeichen an das Spiel


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _approach(current: float, target: float, dt: float, tau: float) -> float:
    """Erstes Ordnung: naehert sich dem Ziel mit Zeitkonstante `tau`."""
    g = _clamp(dt / max(tau, 1e-4), 0.0, 1.0)
    return current + (target - current) * g


def _slew(current: float, target: float, dt: float,
          rise: float = TORQUE_RISE, fall: float = TORQUE_FALL) -> float:
    """Mit begrenzter Steilheit auf das Ziel zu - kein Sprung, kein Treppchen."""
    up = rise * dt
    down = fall * dt
    if target > current:
        return min(target, current + up)
    return max(target, current - down)


def _read_float(value, fallback: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def _wheel_axis_or_none(wheel):
    """Rohwert der DirectInput-Achse (0..65535), oder None.

    `None` heisst "keine belastbare Aussage": kein Rad, keine Achsendaten,
    oder ein Wert ausserhalb des Achsenbereichs. Genau diese Unterscheidung
    braucht das Spiel - es leitet daraus die Kraftrichtung ab
    (`ffb_link.gd::measure_direction`) und darf dabei nichts erfinden.
    """
    if wheel is None:
        return None
    reader = getattr(wheel, "read_axis", None)
    if reader is None:
        return None
    try:
        value = reader()
    except Exception:
        return None
    if value is None:
        return None
    try:
        value = int(value)
    except (TypeError, ValueError):
        return None
    if 0 <= value <= 65535:
        return value
    return None


class GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", DWORD),
        ("Data2", WORD),
        ("Data3", WORD),
        ("Data4", ctypes.c_ubyte * 8),
    ]

    def __str__(self) -> str:
        d4 = "".join(f"{b:02X}" for b in self.Data4)
        return (f"{{{self.Data1:08X}-{self.Data2:04X}-{self.Data3:04X}-"
                f"{d4[:4]}-{d4[4:]}}}")


def guid(text: str) -> GUID:
    """'{BF798031-483A-4DA2-AA99-5D64ED369700}' -> GUID."""
    raw = text.strip().strip("{}").replace("-", "")
    data4 = (ctypes.c_ubyte * 8)(*bytes.fromhex(raw[16:32]))
    return GUID(int(raw[0:8], 16), int(raw[8:12], 16), int(raw[12:16], 16), data4)


IID_IDirectInput8W = guid("{BF798031-483A-4DA2-AA99-5D64ED369700}")
GUID_ConstantForce = guid("{13541C20-8E33-11D0-9AD0-00A0C9A06E1F}")
GUID_Sine = guid("{13541C23-8E33-11D0-9AD0-00A0C9A06E1F}")
GUID_Spring = guid("{13541C27-8E33-11D0-9AD0-00A0C9A06E1F}")
GUID_Damper = guid("{13541C28-8E33-11D0-9AD0-00A0C9A06E1F}")
GUID_Friction = guid("{13541C2A-8E33-11D0-9AD0-00A0C9A06E1F}")
GUID_XAxis = guid("{A36D02E0-C9F3-11CF-BFC7-444553540000}")
GUID_YAxis = guid("{A36D02E1-C9F3-11CF-BFC7-444553540000}")
GUID_ZAxis = guid("{A36D02E2-C9F3-11CF-BFC7-444553540000}")
GUID_RxAxis = guid("{A36D02F4-C9F3-11CF-BFC7-444553540000}")


class DIOBJECTDATAFORMAT(ctypes.Structure):
    _fields_ = [
        ("pguid", ctypes.POINTER(GUID)),
        ("dwOfs", DWORD),
        ("dwType", DWORD),
        ("dwFlags", DWORD),
    ]


class DIDATAFORMAT(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("dwObjSize", DWORD),
        ("dwFlags", DWORD),
        ("dwDataSize", DWORD),
        ("dwNumObjs", DWORD),
        ("rgodf", ctypes.POINTER(DIOBJECTDATAFORMAT)),
    ]


class DIDEVICEINSTANCEW(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("guidInstance", GUID),
        ("guidProduct", GUID),
        ("dwDevType", DWORD),
        ("tszInstanceName", ctypes.c_wchar * MAX_PATH),
        ("tszProductName", ctypes.c_wchar * MAX_PATH),
        ("guidFFDriver", GUID),
        ("wUsagePage", WORD),
        ("wUsage", WORD),
    ]


class DIDEVCAPS(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("dwFlags", DWORD),
        ("dwDevType", DWORD),
        ("dwAxes", DWORD),
        ("dwButtons", DWORD),
        ("dwPOVs", DWORD),
        ("dwFFSamplePeriod", DWORD),
        ("dwFFMinTimeResolution", DWORD),
        ("dwFirmwareRevision", DWORD),
        ("dwHardwareRevision", DWORD),
        ("dwFFDriverVersion", DWORD),
    ]


class DIDEVICEOBJECTINSTANCEW(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("guidType", GUID),
        ("dwOfs", DWORD),
        ("dwType", DWORD),
        ("dwFlags", DWORD),
        ("tszName", ctypes.c_wchar * MAX_PATH),
        ("dwFFMaxForce", DWORD),
        ("dwFFForceResolution", DWORD),
        ("wCollectionNumber", WORD),
        ("wDesignatorIndex", WORD),
        ("wUsagePage", WORD),
        ("wUsage", WORD),
        ("dwDimension", DWORD),
        ("wExponent", WORD),
        ("wReportId", WORD),
    ]


DIDC_FORCEFEEDBACK = 0x00000100
DIDC_FFATTACK = 0x00000200
DIDC_FFFADE = 0x00000400
DIDC_EMULATED = 0x00040000

DIDFT_FFACTUATOR = 0x01000000
DIDFT_FFEFFECTTRIGGER = 0x02000000

DIEFF_OBJECTIDS = 0x00000001


class DICONSTANTFORCE(ctypes.Structure):
    _fields_ = [("lMagnitude", LONG)]


class DICONDITION(ctypes.Structure):
    _fields_ = [
        ("lOffset", LONG),
        ("lPositiveCoefficient", LONG),
        ("lNegativeCoefficient", LONG),
        ("dwPositiveSaturation", DWORD),
        ("dwNegativeSaturation", DWORD),
        ("lDeadBand", LONG),
    ]


class DIPERIODIC(ctypes.Structure):
    _fields_ = [
        ("dwMagnitude", DWORD),
        ("lOffset", LONG),
        ("dwPhase", DWORD),
        ("dwPeriod", DWORD),
    ]


class DIEFFECTINFOW(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("guid", GUID),
        ("dwEffType", DWORD),
        ("dwStaticParams", DWORD),
        ("dwDynamicParams", DWORD),
        ("tszName", ctypes.c_wchar * MAX_PATH),
    ]


class DIEFFECT(ctypes.Structure):
    _fields_ = [
        ("dwSize", DWORD),
        ("dwFlags", DWORD),
        ("dwDuration", DWORD),
        ("dwSamplePeriod", DWORD),
        ("dwGain", DWORD),
        ("dwTriggerButton", DWORD),
        ("dwTriggerRepeatInterval", DWORD),
        ("cAxes", DWORD),
        ("rgdwAxes", ctypes.POINTER(DWORD)),
        ("rglDirection", ctypes.POINTER(LONG)),
        ("lpEnvelope", ctypes.c_void_p),
        ("cbTypeSpecificParams", DWORD),
        ("lpvTypeSpecificParams", ctypes.c_void_p),
        ("dwStartDelay", DWORD),
    ]


def _method(ptr, index: int, restype, *argtypes):
    """COM-Aufruf ueber die vtable: Methode `index` auf dem Objekt `ptr`."""
    table = ctypes.cast(ptr, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p)))[0]
    proto = ctypes.WINFUNCTYPE(restype, ctypes.c_void_p, *argtypes)
    return proto(table[index])


def hr_text(hr: int) -> str:
    known = {
        DI_OK: "DI_OK",
        DIERR_UNSUPPORTED: "DIERR_UNSUPPORTED (Geraet kann das nicht)",
        DIERR_DEVICENOTREG: "DIERR_DEVICENOTREG (nicht als FF-Geraet registriert)",
        DIERR_ACQUIRED: "DIERR_ACQUIRED",
        DIERR_INPUTLOST: "DIERR_INPUTLOST (Eingabe verloren)",
        DIERR_NOTACQUIRED: "DIERR_NOTACQUIRED (Geraet nicht uebernommen)",
        DIERR_DEVICEFULL: "DIERR_DEVICEFULL (keine Effektplaetze frei)",
        DIERR_UNPLUGGED: "DIERR_UNPLUGGED (kein Saft am Lenkrad?)",
    }
    return known.get(hr, f"HRESULT 0x{hr & 0xFFFFFFFF:08X}")


def success(hr: int) -> bool:
    return hr == 0 or hr == 1


class WheelError(RuntimeError):
    pass


## Die Raeder, die der Auftrag nennt. Gesucht wird nach diesen Namensteilen,
## nicht nach einem einzelnen: ein fest auf "G29" gestellter Filter hat ein
## angeschlossenes G920/G923 schlicht nicht gefunden ("kein Lenkrad gefunden,
## dessen Name 'G29' enthaelt"), obwohl es dieselben DirectInput-Effekte
## annimmt. Alle drei melden sich als "Logitech G29/G920/G923 Driving Force
## Racing Wheel"; `--name` ueberschreibt die Liste fuer alles andere.
WHEEL_NAME_NEEDLES = ("g29", "g920", "g923")


def wheel_name_matches(product: str, instance: str = "",
                       needles: tuple = WHEEL_NAME_NEEDLES) -> bool:
    """Traegt dieses DirectInput-Geraet einen der gesuchten Namen?"""
    haystack = f"{product} {instance}".lower()
    return any(needle and needle in haystack for needle in needles)


def wheel_name_needles(name_filter=None) -> tuple:
    """`None` oder "" -> die ganze Familie; sonst die genannten Namensteile.

    Mehrere Namen duerfen mit Komma getrennt werden ("g29,g923"), damit sich
    auch eine eigene Liste bequem auf der Kommandozeile angeben laesst.
    """
    if name_filter is None:
        return WHEEL_NAME_NEEDLES
    if isinstance(name_filter, (list, tuple)):
        parts = [str(p) for p in name_filter]
    else:
        parts = str(name_filter).split(",")
    wanted = tuple(p.strip().lower() for p in parts if p and p.strip())
    return wanted or WHEEL_NAME_NEEDLES


class G29ForceFeedback:
    """Oeffnet das Lenkrad ueber DirectInput und haelt die vier Effekte."""

    def __init__(self, name_filter=None, verbose: bool = False,
                 exclusive: bool = False) -> None:
        self.verbose = verbose
        self.exclusive = exclusive
        self.name = ""
        self.effects_created: list[str] = []
        self.effects_failed: list[str] = []
        self.dinput = ctypes.c_void_p()
        self.device = ctypes.c_void_p()
        self.eff_constant = ctypes.c_void_p()
        self.eff_damper = ctypes.c_void_p()
        self.eff_friction = ctypes.c_void_p()
        self.eff_rumble = ctypes.c_void_p()
        self.eff_spring = ctypes.c_void_p()
        self._hwnd = None
        # Was zuletzt ans Geraet geschickt wurde: ein Effekt wird nur dann neu
        # hochgeladen, wenn sich sein Wert wirklich geaendert hat. Bei 200 Hz
        # sind das sonst tausend DirectInput-Aufrufe je Sekunde ohne Wirkung.
        self._constant_sent = False
        self._damper_sent = False
        self._friction_sent = False
        self._spring_sent = False
        self._axis_offsets = (DWORD * 1)(0)
        self._direction = (LONG * 1)(0)
        self.caps_flags = 0
        self.caps_axes = 0
        self.ff_driver_version = 0
        self.ff_axis_id = 0
        self.objects: list[dict] = []
        self.effect_axis_mode = "offset"
        self._open(name_filter)

    def _open(self, name_filter: str) -> None:
        self._dll = ctypes.WinDLL("dinput8.dll")
        self._user32 = ctypes.WinDLL("user32", use_last_error=True)
        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        # Ohne restype schneidet ctypes das Handle auf 32 Bit ab, und
        # DirectInput antwortet dann mit E_INVALIDARG (0x80070057).
        self._kernel32.GetModuleHandleW.restype = ctypes.c_void_p
        self._kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
        try:
            ctypes.WinDLL("ole32").CoInitialize(None)
        except OSError:
            pass

        self._dll.DirectInput8Create.restype = HRESULT
        self._dll.DirectInput8Create.argtypes = [
            ctypes.c_void_p, DWORD, ctypes.POINTER(GUID),
            ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p,
        ]
        hinst = self._kernel32.GetModuleHandleW(None)
        hr = self._dll.DirectInput8Create(
            hinst, DIRECTINPUT_VERSION, ctypes.byref(IID_IDirectInput8W),
            ctypes.byref(self.dinput), None)
        if not success(hr):
            raise WheelError(f"DirectInput8Create: {hr_text(hr)}")

        self._open_device(name_filter)

        self._set_data_format()
        self._set_cooperative_level()
        self._acquire()
        self._read_caps()
        self._enum_objects()
        self._resolve_effects()
        self._create_effects()

    def _resolve_effects(self) -> None:
        """Die vom Geraet gemeldeten Effekt-GUIDs uebernehmen.

        Der Logitech-Treiber registriert seine Effekte unter eigenen GUIDs
        (`...-00A0C9A06E35`), nicht unter den Standardwerten
        (`...-00A0C9A06E1F`). Ein CreateEffect mit der Standard-GUID endet
        deshalb mit DIERR_DEVICENOTREG (0x80040154) - genau der Fehler, der
        hier zuerst auftrat. Das Geraet weiss es besser: wir fragen es.
        """
        self.effect_guids = {
            "const": GUID_ConstantForce,
            "spring": GUID_Spring,
            "damper": GUID_Damper,
            "friction": GUID_Friction,
            "rumble": GUID_Sine,
        }
        wanted = {
            "const": ("constant", 0x01),
            "spring": ("spring", 0x04),
            "damper": ("damper", 0x04),
            "friction": ("friction", 0x04),
            "rumble": ("sine", 0x03),
        }
        found = self.enum_effects()
        if self.verbose:
            print(f"[ffb] Effektliste: {len(found)} Eintraege")
        if not found:
            return
        for key, (needle, kind) in wanted.items():
            for info in found:
                name = info["name"].lower()
                if needle in name and (info["type"] & 0xFF) == kind:
                    self.effect_guids[key] = info["guid_obj"]
                    break
        self.effects_standard_guids = all(
            self.effect_guids[k] == v for k, v in
            {"const": GUID_ConstantForce, "spring": GUID_Spring,
             "damper": GUID_Damper, "friction": GUID_Friction,
             "rumble": GUID_Sine}.items())
        if self.verbose:
            for key, g in self.effect_guids.items():
                print(f"[ffb] effekt {key}: {g}")

    def ff_supported(self) -> bool:
        return bool(self.caps_flags & DIDC_FORCEFEEDBACK)

    def _read_caps(self) -> None:
        caps = DIDEVCAPS()
        caps.dwSize = ctypes.sizeof(DIDEVCAPS)
        hr = _method(self.device, 3, HRESULT, ctypes.POINTER(DIDEVCAPS))(
            self.device, ctypes.byref(caps))
        if not success(hr):
            return
        self.caps_flags = int(caps.dwFlags)
        self.caps_axes = int(caps.dwAxes)
        self.ff_driver_version = int(caps.dwFFDriverVersion)
        if self.verbose:
            print(f"[ffb] Faehigkeiten: flags=0x{self.caps_flags:08X} "
                  f"achsen={self.caps_axes} FF-Treiber={self.ff_driver_version}")

    def _enum_objects(self) -> None:
        callback_type = ctypes.WINFUNCTYPE(
            wintypes.BOOL, ctypes.POINTER(DIDEVICEOBJECTINSTANCEW), ctypes.c_void_p)

        def _cb(obj_ptr, _ref):
            obj = obj_ptr.contents
            entry = {
                "name": obj.tszName,
                "offset": int(obj.dwOfs),
                "type": int(obj.dwType),
                "flags": int(obj.dwFlags),
                "ff_max_force": int(obj.dwFFMaxForce),
                "ff_actuator": bool(obj.dwType & DIDFT_FFACTUATOR),
                "axis": bool(obj.dwType & DIDFT_ABSAXIS),
            }
            self.objects.append(entry)
            if entry["ff_actuator"] and self.ff_axis_id == 0:
                self.ff_axis_id = entry["type"]
            return True

        enum = _method(self.device, 4, HRESULT, callback_type, ctypes.c_void_p, DWORD)
        enum(self.device, callback_type(_cb), None, 0)
        if self.verbose:
            for o in self.objects:
                mark = " FF" if o["ff_actuator"] else ""
                print(f"[ffb]   objekt {o['name']!r} offset={o['offset']} "
                      f"type=0x{o['type']:08X} maxforce={o['ff_max_force']}{mark}")

    def _open_device(self, name_filter=None) -> None:
        """Geraet im Enum-Callback erzeugen.

        CreateDevice MUSS hier drin passieren: die Instanz-GUID eines
        DirectInput-Geraets ist nur waehrend der Aufzaehlung gueltig. Wird sie
        gespeichert und danach benutzt, antwortet Windows mit
        DIERR_DEVICENOTREG (0x80040154) - genau der Fehler, der hier zuerst
        auftrat.

        Gesucht wird nach der ganzen Familie (G29/G920/G923), nicht nach einem
        einzelnen Namen: derselbe DirectInput-Code bedient alle drei.
        """
        callback_type = ctypes.WINFUNCTYPE(
            wintypes.BOOL, ctypes.POINTER(DIDEVICEINSTANCEW), ctypes.c_void_p)
        needles = wheel_name_needles(name_filter)
        seen: list[str] = []
        found: list[str] = []
        create = _method(self.dinput, 3, HRESULT, ctypes.POINTER(GUID),
                         ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p)

        def _cb(inst_ptr, _ref):
            inst = inst_ptr.contents
            product = inst.tszProductName
            seen.append(product)
            if not wheel_name_matches(product, inst.tszInstanceName, needles):
                return True
            device = ctypes.c_void_p()
            hr = create(self.dinput, ctypes.byref(inst.guidInstance),
                        ctypes.byref(device), None)
            if success(hr) and device:
                self.device = device
                found.append(product)
                return False  # fertig, nicht weiter aufzaehlen
            return True

        enum = _method(self.dinput, 4, HRESULT, DWORD, callback_type,
                       ctypes.c_void_p, DWORD)
        hr = enum(self.dinput, DI8DEVCLASS_GAMECTRL, callback_type(_cb), None,
                  DIEDFL_ATTACHEDONLY)
        if not success(hr):
            raise WheelError(f"EnumDevices: {hr_text(hr)}")
        if self.verbose:
            print(f"[ffb] DirectInput-Gamecontroller: {', '.join(seen) or '(keine)'}")
        if not found:
            raise WheelError(
                f"kein Lenkrad gefunden, dessen Name einen von "
                f"{', '.join(repr(n) for n in needles)} enthaelt "
                f"(DirectInput sieht: {', '.join(seen) or 'nichts'}). "
                f"Anderes Rad? Dann den Namen mit --name angeben.")
        self.name = found[0]
        if self.verbose:
            print(f"[ffb] Geraet: {self.name}")

    def _set_data_format(self) -> None:
        # Eigene, minimale Datenstruktur: eine Absolutachse (Lenkwinkel) an
        # Offset 0. Mehr braucht die Kraft nicht.
        self._obj = DIOBJECTDATAFORMAT(
            ctypes.pointer(GUID_XAxis), 0,
            DIDFT_AXIS | DIDFT_ANYINSTANCE, DIDOI_ASPECTPOSITION)
        self._data_format = DIDATAFORMAT(
            ctypes.sizeof(DIDATAFORMAT), ctypes.sizeof(DIOBJECTDATAFORMAT),
            DIDF_ABSAXIS, 32, 1, ctypes.pointer(self._obj))
        set_fmt = _method(self.device, 11, HRESULT, ctypes.POINTER(DIDATAFORMAT))
        hr = set_fmt(self.device, ctypes.byref(self._data_format))
        if not success(hr):
            raise WheelError(f"SetDataFormat: {hr_text(hr)}")

    def _set_cooperative_level(self) -> None:
        self._user32.CreateWindowExW.restype = ctypes.c_void_p
        self._user32.CreateWindowExW.argtypes = [
            DWORD, ctypes.c_wchar_p, ctypes.c_wchar_p, DWORD,
            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p,
        ]
        hinst = self._kernel32.GetModuleHandleW(None)
        self._hwnd = self._user32.CreateWindowExW(
            0, "STATIC", "ApexCircuitFFB", 0, 0, 0, 0, 0, None, None, hinst, None)
        if not self._hwnd:
            raise WheelError("kein Fensterhandle fuer DirectInput")
        # NONEXCLUSIVE + BACKGROUND ist Pflicht: das Spiel liest dasselbe
        # Lenkrad gleichzeitig ueber SDL; eine exclusive Uebernahme wuerde die
        # Lenkung im Spiel abschalten.
        set_coop = _method(self.device, 13, HRESULT, ctypes.c_void_p, DWORD)
        flags = DISCL_BACKGROUND
        flags |= DISCL_EXCLUSIVE if self.exclusive else DISCL_NONEXCLUSIVE
        hr = set_coop(self.device, ctypes.c_void_p(self._hwnd), flags)
        if not success(hr):
            raise WheelError(f"SetCooperativeLevel: {hr_text(hr)}")

    def _acquire(self) -> None:
        hr = _method(self.device, 7, HRESULT)(self.device)
        if not success(hr):
            raise WheelError(f"Acquire: {hr_text(hr)}")

    def _dieff(self, axes=None, use_ids: bool = False) -> DIEFFECT:
        eff = DIEFFECT()
        eff.dwSize = ctypes.sizeof(DIEFFECT)
        eff.dwFlags = (DIEFF_OBJECTIDS if use_ids else DIEFF_OBJECTOFFSETS) | DIEFF_CARTESIAN
        eff.dwDuration = 0xFFFFFFFF
        eff.dwSamplePeriod = 0
        eff.dwGain = 10000
        eff.dwTriggerButton = DIEB_NONE
        eff.dwTriggerRepeatInterval = 0
        eff.cAxes = 1
        eff.rgdwAxes = axes if axes is not None else self._axis_offsets
        eff.rglDirection = self._direction
        return eff

    def _create_effect(self, effect_guid: GUID, params, label: str,
                       use_ids: bool = False):
        axes = (DWORD * 1)(self.ff_axis_id) if use_ids else None
        eff = self._dieff(axes, use_ids)
        eff.cbTypeSpecificParams = ctypes.sizeof(params)
        eff.lpvTypeSpecificParams = ctypes.cast(ctypes.pointer(params), ctypes.c_void_p)
        create = _method(self.device, 18, HRESULT, ctypes.POINTER(GUID),
                         ctypes.POINTER(DIEFFECT), ctypes.POINTER(ctypes.c_void_p),
                         ctypes.c_void_p)
        out = ctypes.c_void_p()
        hr = create(self.device, ctypes.byref(effect_guid), ctypes.byref(eff),
                    ctypes.byref(out), None)
        if not success(hr):
            mode = "id" if use_ids else "offset"
            self.effects_failed.append(f"{label}[{mode}]: {hr_text(hr)}")
            return None
        hr_dl = _method(out, 10, HRESULT)(out)
        if not success(hr_dl):
            self.effects_failed.append(f"{label} Download: {hr_text(hr_dl)}")
            return None
        hr_start = _method(out, 7, HRESULT, DWORD, DWORD)(out, 1, 0)
        if not success(hr_start):
            self.effects_failed.append(f"{label} Start: {hr_text(hr_start)}")
        self.effects_created.append(label)
        return out

    def _create_effects(self) -> None:
        # Zwei Wege, die Achse zu benennen: ueber den Offset in der
        # Datenstruktur oder ueber die Objekt-ID, die das Geraet selbst
        # meldet. Treiber sind sich da nicht einig, also beide versuchen.
        for use_ids in (False, True):
            self.effects_created.clear()
            self.effects_failed.clear()
            if use_ids and self.ff_axis_id == 0:
                continue
            if self._build_effects(use_ids):
                self.effect_axis_mode = "id" if use_ids else "offset"
                if self.verbose:
                    print(f"[ffb] Achsangabe: {self.effect_axis_mode}")
                return

    def install_format(self, kind: str) -> None:
        """Alternative Datenformate fuer die Effekt-Diagnose."""
        # Ein uebernommenes Geraet nimmt kein neues Format an (ERROR_BUSY).
        unacquire = _method(self.device, 8, HRESULT)
        unacquire(self.device)
        ff_flag = DIDFT_FFACTUATOR if kind.endswith("_ff") else 0
        base = kind[:-3] if kind.endswith("_ff") else kind
        if base == "min":
            specs = [(GUID_XAxis, 0, 0)]
            data_size = 32
        elif base == "min_aspect":
            specs = [(GUID_XAxis, 0, DIDOI_ASPECTPOSITION)]
            data_size = 32
        elif base == "four":
            specs = [(GUID_XAxis, 0, 0), (GUID_YAxis, 4, 0),
                     (GUID_ZAxis, 8, 0), (GUID_RxAxis, 12, 0)]
            data_size = 32
        elif base == "four_aspect":
            specs = [(GUID_XAxis, 0, DIDOI_ASPECTPOSITION),
                     (GUID_YAxis, 4, DIDOI_ASPECTPOSITION),
                     (GUID_ZAxis, 8, DIDOI_ASPECTPOSITION),
                     (GUID_RxAxis, 12, DIDOI_ASPECTPOSITION)]
            data_size = 32
        else:
            raise WheelError(f"unbekanntes Datenformat {kind}")
        objs = (DIOBJECTDATAFORMAT * len(specs))()
        self._obj_refs = []
        for i, (g, off, flags) in enumerate(specs):
            g_ref = ctypes.pointer(g)
            self._obj_refs.append(g_ref)
            objs[i] = DIOBJECTDATAFORMAT(g_ref, off,
                                         DIDFT_AXIS | DIDFT_ANYINSTANCE | ff_flag,
                                         flags)
        self._data_format = DIDATAFORMAT(
            ctypes.sizeof(DIDATAFORMAT), ctypes.sizeof(DIOBJECTDATAFORMAT),
            DIDF_ABSAXIS, data_size, len(specs), objs)
        self._format_array = objs
        set_fmt = _method(self.device, 11, HRESULT, ctypes.POINTER(DIDATAFORMAT))
        hr = set_fmt(self.device, ctypes.byref(self._data_format))
        self._acquire()
        if not success(hr):
            raise WheelError(f"SetDataFormat({kind}): {hr_text(hr)}")

    def enum_effects(self) -> list[dict]:
        """Welche Effektarten kennt das Geraet wirklich?"""
        callback_type = ctypes.WINFUNCTYPE(
            wintypes.BOOL, ctypes.POINTER(DIEFFECTINFOW), ctypes.c_void_p)
        out: list[dict] = []

        def _cb(info_ptr, _ref):
            info = info_ptr.contents
            # WICHTIG: eine echte Kopie. `info.guid` ist nur eine Sicht auf den
            # Speicher des Callbacks, den DirectInput fuer den naechsten
            # Eintrag wiederverwendet - ohne Kopie zeigen am Ende alle
            # Eintraege auf denselben (letzten) Effekt.
            out.append({"guid": str(info.guid),
                        "guid_obj": GUID.from_buffer_copy(info.guid),
                        "name": info.tszName, "type": int(info.dwEffType)})
            return True

        enum = _method(self.device, 19, HRESULT, callback_type, ctypes.c_void_p, DWORD)
        hr = enum(self.device, callback_type(_cb), None, 0)
        if not success(hr):
            print(f"EnumEffects: {hr_text(hr)}")
            return out
        return out

    def matrix(self) -> None:
        """Alle Kombinationen aus Datenformat und Achsangabe durchprobieren."""
        print(f"Geraet   : {self.name}")
        print(f"caps     : 0x{self.caps_flags:08X} FF={self.ff_supported()} "
              f"achsen={self.caps_axes} treiber={self.ff_driver_version}")
        print(f"FF-Aktor-ID: 0x{self.ff_axis_id:08X}")
        print(f"GUID const : {GUID_ConstantForce}")
        for info in self.enum_effects():
            print(f"Effekt     : {info['name']} {info['guid']} type=0x{info['type']:08X}")
        # Manche Logitech-Treiber wollen die Aktoren erst eingeschaltet haben.
        send_cmd = _method(self.device, 22, HRESULT, DWORD)
        for label, cmd in (("RESET", 0x01), ("STOPALL", 0x02),
                           ("ACTUATORSON", 0x10)):
            hr_cmd = send_cmd(self.device, cmd)
            print(f"FF-Kommando {label:12s}: {hr_text(hr_cmd)}")
        for kind in ("min", "min_ff", "min_aspect", "min_aspect_ff", "four"):
            try:
                self.install_format(kind)
            except WheelError as exc:
                print(f"{kind:11s} Format: {exc}")
                continue
            for use_ids in (False, True):
                for acquired in (True, False):
                    if not acquired:
                        _method(self.device, 8, HRESULT)(self.device)
                    params = DICONSTANTFORCE(0)
                    axes = (DWORD * 1)(self.ff_axis_id) if use_ids else None
                    eff = self._dieff(axes, use_ids)
                    eff.cbTypeSpecificParams = ctypes.sizeof(params)
                    eff.lpvTypeSpecificParams = ctypes.cast(
                        ctypes.pointer(params), ctypes.c_void_p)
                    create = _method(self.device, 18, HRESULT,
                                     ctypes.POINTER(GUID), ctypes.POINTER(DIEFFECT),
                                     ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p)
                    out = ctypes.c_void_p()
                    hr = create(self.device, ctypes.byref(GUID_ConstantForce),
                                ctypes.byref(eff), ctypes.byref(out), None)
                    mode = "id" if use_ids else "offset"
                    state = "acq" if acquired else "free"
                    print(f"{kind:11s} {mode:6s} {state:4s}: {hr_text(hr)}")
                    if success(hr) and out:
                        _method(out, 2, ctypes.c_ulong)(out)
                    if not acquired:
                        self._acquire()

    def _build_effects(self, use_ids: bool) -> bool:
        self._constant = DICONSTANTFORCE(0)
        self.eff_constant = self._create_effect(
            self.effect_guids["const"], self._constant, "const", use_ids)

        self._damper = DICONDITION(0, 0, 0, 0, 0, 0)
        self.eff_damper = self._create_effect(
            self.effect_guids["damper"], self._damper, "damper", use_ids)

        self._friction = DICONDITION(0, 0, 0, 0, 0, 0)
        self.eff_friction = self._create_effect(
            self.effect_guids["friction"], self._friction, "friction", use_ids)

        # Zentrierfeder: das Lenkrad zieht von selbst zurueck in die Mitte -
        # das ist die Kraft, die ein Fahrer am staerksten spuert.
        self._spring = DICONDITION(0, 0, 0, 0, 0, 0)
        self.eff_spring = self._create_effect(
            self.effect_guids["spring"], self._spring, "spring", use_ids)

        self._periodic = DIPERIODIC(0, 0, 0, 24000)
        self.eff_rumble = self._create_effect(
            self.effect_guids["rumble"], self._periodic, "rumble", use_ids)
        return bool(self.effects_created)

    # -- Betrieb -----------------------------------------------------------

    def read_axis(self):
        """Rohwert der Lenkachse, oder None wenn das Lenkrad nichts liefert."""
        _method(self.device, 25, HRESULT)(self.device)
        state = (ctypes.c_byte * 32)()
        hr = _method(self.device, 9, HRESULT, DWORD, ctypes.c_void_p)(
            self.device, ctypes.sizeof(state), ctypes.byref(state))
        if not success(hr):
            if hr in (DIERR_NOTACQUIRED, DIERR_INPUTLOST):
                try:
                    self._acquire()
                except WheelError:
                    return None
            return None
        if all(b == 0 for b in state):
            # Ein stromloses G29 liefert Nullbytes auf jeder Achse.
            return None
        return ctypes.cast(state, ctypes.POINTER(LONG)).contents.value

    def apply(self, force: float, damp: float, fric: float, rumble: float,
              pulse: float, invert: bool = False, spring: float = 0.0,
              rumble_hz: float = 24.0, gain: float = 1.0,
              pulse_dir: float = 0.0) -> None:
        """Kraefte ans Lenkrad geben.

        `force` ist die Grundkraft (-1..+1, + = nach rechts), `pulse` ein
        zusaetzlicher kurzer Stoss in Richtung `pulse_dir`. `gain` ist der
        manuelle Trimm aus `--gain` und skaliert beides - die Staerke aus dem
        Spiel steckt schon in `force` und wird hier **nicht** noch einmal
        angewendet.
        """
        sign = -1.0 if invert else 1.0
        g = _clamp(gain, 0.0, 1.0)
        burst = _clamp(pulse, 0.0, 1.0) * g * PULSE_MIX * _clamp(pulse_dir, -1.0, 1.0)
        total = _clamp(_clamp(force, -1.0, 1.0) * g + burst, -1.0, 1.0)
        magnitude = int(total * 10000 * sign)
        self._set_constant(magnitude)
        self._set_damper(int(_clamp(damp, 0.0, 1.0) * 7000))
        self._set_friction(int(_clamp(fric, 0.0, 1.0) * 7000))
        self._set_spring(int(_clamp(spring, 0.0, 1.0) * 9000))
        self._set_rumble(int(_clamp(rumble, 0.0, 1.0) * 8000), rumble_hz)

    def _set_constant(self, magnitude: int) -> None:
        if not self.eff_constant:
            return
        if magnitude == self._constant.lMagnitude and self._constant_sent:
            return
        self._constant.lMagnitude = magnitude
        self._constant_sent = True
        self._update(self.eff_constant, self._constant)

    def _set_damper(self, coefficient: int) -> None:
        if not self.eff_damper:
            return
        if coefficient == self._damper.lPositiveCoefficient and self._damper_sent:
            return
        self._damper.lPositiveCoefficient = coefficient
        self._damper.lNegativeCoefficient = -coefficient
        self._damper_sent = True
        self._update(self.eff_damper, self._damper)

    def _set_friction(self, coefficient: int) -> None:
        if not self.eff_friction:
            return
        if coefficient == self._friction.lPositiveCoefficient and self._friction_sent:
            return
        self._friction.lPositiveCoefficient = coefficient
        self._friction.lNegativeCoefficient = -coefficient
        self._friction_sent = True
        self._update(self.eff_friction, self._friction)

    def _set_rumble(self, magnitude: int, hz: float = 24.0) -> None:
        """Ruetteln mit Frequenz. Das Geraet kennt `dwPeriod` in Mikrosekunden:
        ein Kerb bei 38 Hz ist damit etwas anderes als Kies bei 11 Hz, und
        beides ist etwas anderes als der feste Wert von frueher."""
        if not self.eff_rumble:
            return
        period = int(_clamp(1_000_000.0 / max(hz, 1.0), 1000.0, 250000.0))
        if magnitude == self._periodic.dwMagnitude and period == self._periodic.dwPeriod:
            return
        self._periodic.dwMagnitude = magnitude
        self._periodic.dwPeriod = period
        self._update(self.eff_rumble, self._periodic)

    def _set_spring(self, coefficient: int) -> None:
        if not self.eff_spring:
            return
        if coefficient == self._spring.lPositiveCoefficient and self._spring_sent:
            return
        self._spring.lOffset = 0
        self._spring.lPositiveCoefficient = coefficient
        self._spring.lNegativeCoefficient = -coefficient
        self._spring_sent = True
        self._update(self.eff_spring, self._spring)

    def _update(self, effect, params) -> None:
        eff = self._dieff()
        eff.cbTypeSpecificParams = ctypes.sizeof(params)
        eff.lpvTypeSpecificParams = ctypes.cast(ctypes.pointer(params), ctypes.c_void_p)
        _method(effect, 6, HRESULT, ctypes.POINTER(DIEFFECT), DWORD)(
            effect, ctypes.byref(eff), DIEP_TYPESPECIFICPARAMS)

    def stop_all(self) -> None:
        for effect in (self.eff_constant, self.eff_spring, self.eff_damper,
                       self.eff_friction, self.eff_rumble):
            if effect:
                _method(effect, 8, HRESULT)(effect)

    def close(self) -> None:
        try:
            self.stop_all()
        except Exception:
            pass
        for effect in (self.eff_constant, self.eff_spring, self.eff_damper,
                       self.eff_friction, self.eff_rumble):
            if effect:
                _method(effect, 2, ctypes.c_ulong)(effect)
        if self.device:
            _method(self.device, 2, ctypes.c_ulong)(self.device)
        if self.dinput:
            _method(self.dinput, 2, ctypes.c_ulong)(self.dinput)
        if self._hwnd:
            self._user32.DestroyWindow(ctypes.c_void_p(self._hwnd))


def list_devices() -> int:
    dll = ctypes.WinDLL("dinput8.dll")
    dll.DirectInput8Create.restype = HRESULT
    dll.DirectInput8Create.argtypes = [
        ctypes.c_void_p, DWORD, ctypes.POINTER(GUID),
        ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.GetModuleHandleW.restype = ctypes.c_void_p
    kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
    di = ctypes.c_void_p()
    hr = dll.DirectInput8Create(kernel32.GetModuleHandleW(None), DIRECTINPUT_VERSION,
                                ctypes.byref(IID_IDirectInput8W), ctypes.byref(di), None)
    if not success(hr):
        print(f"DirectInput8Create: {hr_text(hr)}")
        return 1
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL,
                                       ctypes.POINTER(DIDEVICEINSTANCEW), ctypes.c_void_p)
    names: list[str] = []

    def _cb(inst_ptr, _ref):
        inst = inst_ptr.contents
        names.append(f"{inst.tszProductName}  |  {inst.tszInstanceName}")
        return True

    enum = _method(di, 4, HRESULT, DWORD, callback_type, ctypes.c_void_p, DWORD)
    enum(di, DI8DEVCLASS_GAMECTRL, callback_type(_cb), None, DIEDFL_ATTACHEDONLY)
    print(f"DirectInput sieht {len(names)} Gamecontroller:")
    for n in names:
        print("  " + n)
    return 0


def selftest(seconds: float, invert: bool, verbose: bool,
             exclusive: bool = True, name_filter=None) -> int:
    try:
        wheel = G29ForceFeedback(name_filter=name_filter, verbose=verbose,
                                 exclusive=exclusive)
    except WheelError as exc:
        print(f"SELFTEST FAIL: {exc}")
        return 1

    print(f"Geraet      : {wheel.name}")
    print(f"FF-faehig   : {wheel.ff_supported()} (caps=0x{wheel.caps_flags:08X}, "
          f"Achsen={wheel.caps_axes}, FF-Treiber={wheel.ff_driver_version})")
    actuators = [o for o in wheel.objects if o["ff_actuator"]]
    print(f"FF-Aktoren  : {len(actuators)}"
          + ("".join(f" [{o['name']} maxforce={o['ff_max_force']}]" for o in actuators)))
    print(f"Achse ueber : {wheel.effect_axis_mode}")
    print(f"Effekte ok  : {', '.join(wheel.effects_created) or '(keine)'}")
    if wheel.effects_failed:
        print(f"Effekte aus : {'; '.join(wheel.effects_failed)}")

    before = wheel.read_axis()
    print(f"Achse vorher: {before if before is not None else 'keine Achsendaten'}")
    # Kurzer, klar begrenzter Teststoss. Absichtlich schwach, damit ein
    # unbeaufsichtigtes Lenkrad nicht gegen den Anschlag schlaegt.
    deadline = time.time() + seconds
    while time.time() < deadline:
        wheel.apply(force=0.18, damp=0.25, fric=0.15, rumble=0.5, pulse=0.0,
                    invert=invert)
        time.sleep(0.02)
    wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, invert)
    after = wheel.read_axis()
    print(f"Achse nachher: {after if after is not None else 'keine Achsendaten'}")
    wheel.close()

    if not wheel.effects_created:
        print("SELFTEST FAIL: kein einziger Effekt konnte geladen werden")
        return 1
    if before is None or after is None:
        print("SELFTEST TEILWEISE: Effekte geladen und gestartet, aber die Achse "
              "liess sich nicht auslesen (keine Achsendaten). Ohne Netzteil kann "
              "der Motor keine Kraft erzeugen.")
        return 2
    if before == after:
        print("SELFTEST TEILWEISE: Effekte laufen, die Achse hat sich in der kurzen "
              "Zeit aber nicht bewegt (Lenkrad festgehalten oder Kraft zu klein).")
        return 2
    print(f"SELFTEST PASS: Achse bewegte sich von {before} nach {after}")
    return 0


def run_bridge(port: int, rate: float, invert: bool, verbose: bool,
               idle_release: float, exclusive: bool = True,
               spring: float = 0.0, gain: float = 1.0,
               dry_run: bool = False, run_seconds: float = 0.0,
               report: dict = None, quiet: bool = False,
               wheel_override=None, name_filter=None) -> int:
    """Pakete lesen und Kraft ans Lenkrad geben.

    `report` (optional) wird mit den Messwerten des Laufs gefuellt, damit
    `--check` die Kette ohne Hardware pruefen kann, statt sie nur zu drucken:
    Spitzenkraft, groesster Sprung, Anzahl guter/kaputter/v1-Pakete, Quellen,
    Clipping und ob die Kraft am Ende wirklich losgelassen wurde.

    `wheel_override` setzt einen Ersatz fuer das G29 ein (siehe
    `_MagnitudeProbe`). Damit laeuft der echte Loop samt Rampe und Puls, nur
    ohne Hardware - das ist die Messung, die `--check` benutzt.
    """
    wheel = None
    if wheel_override is not None:
        wheel = wheel_override
    elif not dry_run:
        try:
            wheel = G29ForceFeedback(name_filter=name_filter, verbose=verbose,
                                     exclusive=exclusive)
        except WheelError as exc:
            print(f"[ffb] kein Lenkrad: {exc}")
            return 1
        if not quiet:
            print(f"[ffb] {wheel.name} bereit, Effekte: "
                  f"{', '.join(wheel.effects_created) or '(keine)'}")
        if wheel.effects_failed:
            print(f"[ffb] nicht verfuegbar: {'; '.join(wheel.effects_failed)}")
        if not wheel.effects_created:
            print("[ffb] ohne Effekte beendet sich der Helfer")
            wheel.close()
            return 1
    else:
        if not quiet:
            print("[ffb] Trockenlauf: kein Lenkrad, nur die Rechnung "
                  "(zum Pruefen der Kette ohne Hardware)")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Zwei Helfer am selben Port wuerden sich die Pakete teilen: Windows gibt
    # sie dem zuletzt gebundenen Socket. Ein zweimal gestarteter Helfer soll
    # deshalb klar sagen, dass schon einer laeuft, statt den ersten still
    # abzuhaengen. (Fallback fuer Nicht-Windows: SO_REUSEADDR wie bisher.)
    _exclusive = getattr(socket, "SO_EXCLUSIVEADDRUSE", None)
    if _exclusive is not None:
        sock.setsockopt(socket.SOL_SOCKET, _exclusive, 1)
    else:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("127.0.0.1", port))
    except OSError as exc:
        # Laeuft schon ein Helfer (oder hat Windows den Port nach einem
        # abgestuerzten Lauf noch nicht freigegeben), darf das Programm nicht
        # mit einem Traceback sterben: das sieht aus wie ein Fehler im Spiel.
        sock.close()
        print(f"[ffb] Port {port} ist belegt ({exc}). Laeuft schon ein Helfer? "
              f"Anderer Port mit --port oder APEX_FFB_PORT.")
        return 1
    sock.setblocking(False)

    period = 1.0 / max(rate, 20.0)
    # Ziel (was das Spiel will) und Ist (was gleich am Lenkrad liegt). Zwischen
    # beiden liegt die Rampe, damit der Zahnradantrieb nicht springt.
    target = {"torque": 0.0, "damper": 0.0, "fric": 0.0, "rumble": 0.0,
              "rumble_hz": 24.0, "pulse": 0.0, "pulse_dir": 0.0, "spring": spring}
    live = dict(target)
    last_packet = 0.0
    packets = 0
    stale_now = False
    last_report = time.time()
    started = time.time()
    # Messwerte fuer den Trockenlauf: der groesste Sprung, den das Lenkrad
    # wirklich zu sehen bekommt, gegen den groessten Sprung im Paket.
    max_step = 0.0
    max_target_jump = 0.0
    extremes = {"torque": [0.0, 0.0], "damper": [0.0, 0.0],
                "fric": [0.0, 0.0], "rumble": [0.0, 0.0]}
    last_target_torque = 0.0
    # Diagnose aus dem Paket: woher die Kraft kommt und ob sie am Anschlag haengt.
    last_source = "-"
    source_counts = {}
    # Ereignis und Tempo gehoeren zur selben Diagnose: "was ist gerade
    # passiert" (Schalten, Einschlag) und "wie schnell war der Wagen dabei".
    # Ueber das Protokoll kamen beide schon an, gelesen hat sie niemand.
    last_event = ""
    event_counts = {}
    speed_peak = 0.0
    speed_last = 0.0
    clip_max = 0.0
    damage_max = 0.0
    # Echte Spitzen statt Stichproben: `--verbose` druckt alle 2 s eine Zeile,
    # eine Kurve mit 3,5 g haelt aber nur rund eine Sekunde. Wer die Kraft an
    # so einer Zeile abliest, misst den Zufall (genau das passierte: derselbe
    # Lauf meldete einmal 0,560, einmal 0,250). Diese Zahlen entstehen aus
    # jedem Sample des Loops (200 Hz) und werden mitgedruckt.
    hz_peak = 0.0
    over_one = 0
    good_packets = 0
    malformed = 0
    v1_packets = 0
    v2_packets = 0
    # Was das Spiel als Staerke meldet - nur zur Anzeige. Die Kraft selbst
    # kommt schon skaliert an (ffb_model.gd ist die einzige Stelle, die
    # skaliert); `gain` hier ist ausschliesslich der manuelle Trimm von
    # `--gain`.
    reported_gain = gain
    # Lebenszeichen an das Spiel: ohne sie kann das HUD nicht wissen, ob
    # ueberhaupt ein Helfer lauscht. Das Spiel sendet sonst ins Leere, das
    # Lenkrad bleibt still, und der Fahrer sucht den Fehler in der Physik.
    acks_sent = 0
    ## Wie viele dieser Lebenszeichen die eigene Achsenstellung trugen. Das
    ## Spiel braucht sie, um die Kraftrichtung selbst zu messen; im Trockenlauf
    ## (kein Rad) bleibt die Zahl 0, und das ist die ehrliche Aussage.
    acks_with_axis = 0
    last_ack = 0.0
    if not quiet:
        print(f"[ffb] hoert auf 127.0.0.1:{port} ({rate:.0f} Hz)")

    def peak_line() -> str:
        """Eine Zeile mit den echten Spitzenwerten des ganzen Laufs.

        `[ffb]` (alle 2 s) ist eine Stichprobe, `[ffb-peak]` ist das Maximum
        aus jedem Sample des Loops. Die Ende-zu-Ende-Pruefung liest diese
        Zeilen, damit ein kurzer Kurvenscheitel nicht zufaellig durchs Raster
        faellt.
        """
        return (f"[ffb-peak] torque={max(abs(extremes['torque'][0]), abs(extremes['torque'][1])):.3f} "
                f"rumble={extremes['rumble'][1]:.3f} hz={hz_peak:.1f} over={over_one} "
                f"packets={packets} speed={speed_peak:.1f} clip={clip_max:.3f}")
    try:
        while True:
            now = time.time()
            # Der Puls klingt ab, BEVOR neue Pakete gelesen werden: so bekommt
            # ein Stoss, der in diesem Sample ankommt, seine volle Staerke ans
            # Lenkrad (vorher lief die Abklingstufe zuerst und nahm ihm 12 %,
            # gemessen in tools/g29_ffb.py --check).
            live["pulse"] = max(live["pulse"] - period / PULSE_DECAY, 0.0)
            if live["pulse"] <= 0.0:
                live["pulse_dir"] = 0.0
            got = None
            peer = None
            while True:
                try:
                    data, peer = sock.recvfrom(4096)
                except (BlockingIOError, OSError):
                    break
                got = data
            if got:
                try:
                    msg = json.loads(got.decode("utf-8", "replace"))
                except ValueError:
                    msg = None
                if isinstance(msg, dict):
                    packets += 1
                    good_packets += 1
                    last_packet = now
                    # v2: torque; v1 (alte Sender): force. Beides wird gelesen,
                    # damit ein alter Sender den Helfer nicht lahmlegt.
                    if "torque" in msg:
                        v2_packets += 1
                    else:
                        v1_packets += 1
                    torque = msg.get("torque", msg.get("force", 0.0))
                    target["torque"] = _read_float(torque)
                    target["damper"] = _read_float(msg.get("damper", msg.get("damp", 0.0)))
                    target["fric"] = _read_float(msg.get("friction", msg.get("fric", 0.0)))
                    target["rumble"] = _read_float(msg.get("rumble", 0.0))
                    target["rumble_hz"] = _clamp(_read_float(msg.get("rumble_hz", 24.0)), 5.0, 60.0)
                    try:
                        target["spring"] = _clamp(float(msg.get("spring", spring)), 0.0, 1.0)
                    except (TypeError, ValueError):
                        target["spring"] = spring
                    if "gain" in msg:
                        # Keine zweite Skalierung: die Staerke aus dem Spiel
                        # steckt schon im gesendeten `torque`. Wuerde der
                        # Helfer noch einmal damit multiplizieren, waeren die
                        # Stufen quadratisch (75 % -> 56 % Kraft, 45 % -> 20 %).
                        try:
                            reported_gain = _clamp(float(msg["gain"]), 0.0, 1.0)
                        except (TypeError, ValueError):
                            pass
                    # Die Pakete tragen auch, woher die Kraft kommt (source),
                    # wie stark sie am Anschlag haengt (clip) und wie kaputt
                    # das Auto ist (damage). Ohne diese Zeilen waeren sie
                    # blinde Passagiere.
                    last_source = str(msg.get("source", "-"))
                    source_counts[last_source] = source_counts.get(last_source, 0) + 1
                    event = msg.get("event", "")
                    if isinstance(event, str) and event:
                        last_event = event
                        event_counts[event] = event_counts.get(event, 0) + 1
                    speed_last = _read_float(msg.get("speed", 0.0))
                    if speed_last > speed_peak:
                        speed_peak = speed_last
                    clip_max = max(clip_max, _clamp(_read_float(msg.get("clip", 0.0)), 0.0, 1.0))
                    damage_max = max(damage_max, _clamp(_read_float(msg.get("damage", 0.0)), 0.0, 1.0))
                    max_target_jump = max(max_target_jump,
                                          abs(target["torque"] - last_target_torque))
                    last_target_torque = target["torque"]
                    impulse = _clamp(_read_float(msg.get("pulse", 0.0)), 0.0, 1.0)
                    if impulse > 0.02:
                        pdir = _clamp(_read_float(msg.get("pulse_dir", 0.0)), -1.0, 1.0)
                        if impulse >= live["pulse"]:
                            live["pulse"] = impulse
                            live["pulse_dir"] = pdir
                            target["pulse_dir"] = pdir
                    # Lebenszeichen zurueck an den Absender (10 Hz reichen).
                    # Das Spiel liest die Antwort auf demselben Socket, mit dem
                    # es sendet (`ffb_link.gd`), und zeigt im HUD, wenn keiner
                    # antwortet.
                    if peer and now - last_ack >= ACK_PERIOD:
                        last_ack = now
                        # Die eigene Achsenstellung mitgeben: das Spiel liest
                        # dieselbe Achse ueber SDL und kann damit SELBST
                        # messen, wie DirectInput- und SDL-Achse zueinander
                        # stehen - daraus folgt die richtige Kraftrichtung,
                        # ohne dass jemand das Rad mit Kraft drehen muss
                        # (`ffb_link.gd::measure_direction`). Fehlt der Wert,
                        # steht das Feld nicht im Paket: "keine Achsendaten"
                        # darf nie als Messung durchgehen.
                        axis_now = _wheel_axis_or_none(wheel)
                        ack = {
                            "v": 2, "ack": 1,
                            "mode": "dry" if dry_run else "wheel",
                            "torque": round(live["torque"], 3),
                        }
                        if axis_now is not None:
                            ack["axis"] = axis_now
                            acks_with_axis += 1
                        try:
                            sock.sendto(json.dumps(ack).encode("utf-8"), peer)
                            acks_sent += 1
                        except OSError:
                            # Antwortet niemand (Socket schon zu), ist das kein
                            # Fehler: der naechste Versuch trifft wieder.
                            pass
                else:
                    malformed += 1

            stale = (now - last_packet) > idle_release
            stale_now = stale
            if stale:
                # Kein Spiel (mehr) am anderen Ende: Lenkrad loslassen.
                target["torque"] = 0.0
                target["damper"] = 0.10
                target["fric"] = 0.05
                target["rumble"] = 0.0
                target["spring"] = 0.0
                target["pulse"] = 0.0

            before = live["torque"]
            live["torque"] = _slew(live["torque"], _clamp(target["torque"], -1.0, 1.0), period)
            max_step = max(max_step, abs(live["torque"] - before))
            live["damper"] = _approach(live["damper"], _clamp(target["damper"], 0.0, 1.0), period, 0.12)
            live["fric"] = _approach(live["fric"], _clamp(target["fric"], 0.0, 1.0), period, 0.12)
            live["rumble"] = _approach(live["rumble"], _clamp(target["rumble"], 0.0, 1.0), period, 0.05)
            live["rumble_hz"] = _approach(live["rumble_hz"], target["rumble_hz"], period, 0.10)
            if wheel is not None:
                wheel.apply(live["torque"], live["damper"], live["fric"],
                            live["rumble"], live["pulse"], invert, live["spring"],
                            live["rumble_hz"], gain, live["pulse_dir"])
            for key in extremes:
                extremes[key][0] = min(extremes[key][0], live[key])
                extremes[key][1] = max(extremes[key][1], live[key])
            hz_peak = max(hz_peak, live["rumble_hz"])
            if abs(live["torque"]) > 1.0:
                over_one += 1

            if run_seconds > 0.0 and now - started >= run_seconds:
                if report is not None:
                    report.update({
                        "packets": good_packets,
                        "malformed": malformed,
                        "v1_packets": v1_packets,
                        "v2_packets": v2_packets,
                        "max_step": max_step,
                        "max_target_jump": max_target_jump,
                        "peak_torque": max(abs(extremes["torque"][0]),
                                           abs(extremes["torque"][1])),
                        "peak_damper": extremes["damper"][1],
                        "peak_rumble": extremes["rumble"][1],
                        "last_live_torque": live["torque"],
                        "released": stale_now and abs(live["torque"]) < 1e-6,
                        "sources": dict(source_counts),
                        "events": dict(event_counts),
                        "last_event": last_event,
                        "peak_speed": speed_peak,
                        "last_speed": speed_last,
                        "clip_max": clip_max,
                        "damage_max": damage_max,
                        "reported_gain": reported_gain,
                        "acks_sent": acks_sent,
                        "acks_with_axis": acks_with_axis,
                        "hz_peak": hz_peak,
                        "over_one": over_one,
                    })
                if not quiet:
                    print(f"[ffb-dry] {packets} Pakete in {now - started:.1f} s, "
                          f"Rate {rate:.0f} Hz")
                    for key in ("torque", "damper", "fric", "rumble"):
                        print(f"[ffb-dry] {key:7s} {extremes[key][0]:+.3f} .. "
                              f"{extremes[key][1]:+.3f}")
                    print(f"[ffb-dry] groesster Sprung im Paket  {max_target_jump:.3f} "
                          f"(das Spiel sendet mit 60 Hz)")
                    print(f"[ffb-dry] groesster Sprung am Rad    {max_step:.3f} "
                          f"pro Sample ({1.0 / period:.0f} Hz) - Rampe aktiv")
                    print(f"[ffb-dry] Quellen der Kraft          {source_counts or '-'}")
                    print(f"[ffb-dry] Ereignisse                 {event_counts or '-'} "
                          f"bei bis {speed_peak:.0f} km/h")
                    print(f"[ffb-dry] Staerke laut Paket         {reported_gain:.0%} "
                          f"(skaliert die Kraft NICHT ein zweites Mal)")
                    print(f"[ffb-dry] Lebenszeichen ans Spiel    {acks_sent}")
                    print(peak_line())
                    print(f"[ffb-dry] am Ende                    "
                          f"torque={live['torque']:+.3f} "
                          f"({'losgelassen' if stale_now else 'noch gehalten'})")
                return 0

            if verbose and now - last_report > 2.0:
                last_report = now
                print(peak_line())
                print(f"[ffb] {packets} Pakete, torque={live['torque']:+.2f} "
                      f"damp={live['damper']:.2f} fric={live['fric']:.2f} "
                      f"rumble={live['rumble']:.2f}@{live['rumble_hz']:.0f}Hz "
                      f"pulse={live['pulse']:.2f} Staerke={reported_gain:.0%} "
                      f"Quelle={last_source} Clip={clip_max:.0%} "
                      f"Ereignis={last_event or '-'} Tempo={speed_last:.0f}km/h"
                      + (" [idle]" if stale_now else ""))
            time.sleep(period)
    except KeyboardInterrupt:
        print("\n[ffb] beendet")
    finally:
        if wheel is not None:
            wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, invert)
            wheel.close()
    return 0


## ---- Kette ohne Lenkrad pruefen ------------------------------------------
## Diese Pruefung deckt genau die Fehler ab, die sonst erst am Lenkrad
## auffallen wuerden: eine doppelt angewendete Staerke (frueher kamen 75 %
## als 56 % am Rad an, 30 % als 9 %), ein Puls, der zusaetzlich auf die Kraft
## geht, ein kaputtes Paket, das den Helfer aus dem Tritt bringt, und eine
## Kraft, die nach dem Schliessen des Spiels stehen bleibt.
##
##   python tools/g29_ffb.py --check        # Exit 0 = alles gut, 1 = Mangel


def _packet(**fields) -> bytes:
    """Ein Paket wie das Spiel es schickt."""
    return json.dumps(fields).encode("utf-8")


def _free_port(preferred: int = 5611) -> int:
    """Einen freien UDP-Port finden, damit die Pruefung neben dem Spiel laeuft."""
    for candidate in (preferred, preferred + 1, preferred + 2, 0):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("127.0.0.1", candidate))
            return int(sock.getsockname()[1])
        except OSError:
            continue
        finally:
            sock.close()
    return 0


def _send_script(port: int, script, rate: float = 60.0) -> None:
    """`script` ist eine Folge von (Payload, Sekunden); None = Sendepause."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        for payload, seconds in script:
            end = time.time() + seconds
            while time.time() < end:
                if payload is not None:
                    sock.sendto(payload, ("127.0.0.1", port))
                time.sleep(1.0 / rate)
    finally:
        sock.close()


class _MagnitudeProbe:
    """Ersatz fuer das G29, der mitschreibt, welche Kraft `apply` ausgibt.

    Rampe und Puls entstehen erst in `apply` - ohne diese Sonde wuerde eine
    Messung im Trockenlauf genau das uebersehen, was am Lenkrad ankommt.
    """

    def __init__(self) -> None:
        wheel = G29ForceFeedback.__new__(G29ForceFeedback)
        self.wheel = wheel
        self.magnitudes: list = []
        wheel._set_constant = lambda magnitude: self.magnitudes.append(magnitude)
        wheel._set_damper = lambda coefficient: None
        wheel._set_friction = lambda coefficient: None
        wheel._set_spring = lambda coefficient: None
        wheel._set_rumble = lambda magnitude, hz=24.0: None
        wheel.close = lambda: None

    def peak(self) -> float:
        """Groesste Kraft, die wirklich ans Lenkrad ging (Anteil von 1.0)."""
        return max((abs(m) for m in self.magnitudes), default=0) / 10000.0


def _measure(script, run_seconds: float, rate: float = 200.0,
             probe: _MagnitudeProbe = None) -> dict:
    """Den echten Bruecken-Loop mit einem synthetischen Sender messen."""
    port = _free_port()
    report: dict = {}
    sender = threading.Thread(target=_send_script, args=(port, script), daemon=True)
    sender.start()
    run_bridge(port, rate, False, False, 0.5, dry_run=probe is None,
               run_seconds=run_seconds, report=report, quiet=True,
               wheel_override=probe.wheel if probe else None)
    sender.join(timeout=5.0)
    if probe is not None:
        report["peak_wheel"] = probe.peak()
    return report


def _ack_probe(rate: float = 200.0, wait: float = 2.5, wheel=None) -> tuple:
    """Antwortet der Helfer dem Spiel?

    Gegenrichtung zu `_measure`: hier laeuft der echte Bruecken-Loop in einem
    Thread, und die Sonde ist der Sender (wie das Spiel). Ohne diesen
    Rueckkanal kann das HUD nicht sagen, ob ueberhaupt ein Helfer lauscht -
    ein totes Lenkrad waere unsichtbar, weil UDP nichts bestaetigt.

    `wheel` (optional) ersetzt das Lenkrad - damit laesst sich pruefen, dass das
    Lebenszeichen die Achsenstellung des Helfers mitschickt, ohne Hardware.

    Rueckgabe: (bekommen, modus, beschreibung, letzte Antwort)
    """
    port = _free_port()
    report: dict = {}
    worker = threading.Thread(
        target=run_bridge,
        args=(port, rate, False, False, 0.5),
        kwargs=dict(dry_run=True, quiet=True, run_seconds=wait + 1.5,
                    report=report, wheel_override=wheel),
        daemon=True,
    )
    worker.start()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind(("127.0.0.1", 0))
        sock.settimeout(0.2)
        payload = _packet(v=2, torque=0.5, damper=0.0, friction=0.0, rumble=0.0,
                          rumble_hz=24.0, pulse=0.0, pulse_dir=0.0, spring=0.0,
                          gain=1.0, event="", speed=100.0, source="Test")
        deadline = time.time() + wait
        while time.time() < deadline:
            sock.sendto(payload, ("127.0.0.1", port))
            try:
                data, _peer = sock.recvfrom(4096)
            except (socket.timeout, OSError):
                continue
            try:
                msg = json.loads(data.decode("utf-8", "replace"))
            except ValueError:
                continue
            if isinstance(msg, dict) and int(msg.get("ack", 0)) == 1:
                return True, str(msg.get("mode", "")), (
                    f"Antwort {msg} nach {wait - (deadline - time.time()):.2f} s"), msg
        return False, "", f"keine Antwort innerhalb {wait:.1f} s", {}
    finally:
        sock.close()


def check_chain(rate: float = 200.0) -> int:
    """Die Kette Paket -> Kraft ohne Lenkrad pruefen (0 = alles gut)."""
    failed = 0
    checks = 0

    def check(ok: bool, label: str, detail: str = "") -> None:
        nonlocal failed, checks
        checks += 1
        print(("PASS " if ok else "FAIL ") + label + " " + detail)
        if not ok:
            failed += 1

    # 1) Die Staerke steckt schon im gesendeten `torque`. Das `gain`-Feld im
    #    Paket ist nur die Meldung "so stark steht das Menue", es darf die
    #    Kraft nicht ein zweites Mal skalieren.
    v2 = _packet(v=2, torque=0.797, damper=0.2, friction=0.1, rumble=0.0,
                 rumble_hz=30.0, pulse=0.0, pulse_dir=0.0, spring=0.0, gain=0.75,
                 source="Asphalt", clip=0.0, damage=0.0)
    probe = _MagnitudeProbe()
    r = _measure([(v2, 1.0), (None, 1.4)], 2.6, rate, probe)
    peak = float(r.get("peak_torque", 0.0))
    at_wheel = float(r.get("peak_wheel", 0.0))
    check(abs(at_wheel - 0.797) < 0.01, "staerke_wird_genau_einmal_angewendet",
          f"Paket 0.797 mit gain 0.75 -> Rad {at_wheel:.3f} (nicht 0.598)")
    check(bool(r.get("released", False)), "kraft_faellt_nach_dem_letzten_paket",
          f"0,5 s ohne Paket -> torque={float(r.get('last_live_torque', 0.0)):+.3f}")
    check(float(r.get("max_step", 1.0)) <= TORQUE_RISE / rate + 1e-6,
          "rampe_begrenzt_den_sprung",
          f"groesster Sprung {float(r.get('max_step', 0.0)):.3f} pro Sample, "
          f"erlaubt {TORQUE_RISE / rate:.3f} "
          f"({1000.0 / TORQUE_RISE:.0f} ms fuer vollen Ausschlag)")
    check(int(r.get("sources", {}).get("Asphalt", 0)) > 30,
          "das_paket_sagt_woher_die_kraft_kommt", str(r.get("sources", {})))

    # 2) Ein alter Sender (v1: force/damp/fric) darf den Helfer nicht lahmlegen.
    v1 = _packet(v=1, force=0.5, damp=0.2, fric=0.1, rumble=0.0, pulse=0.0,
                 event="test", speed=40.0, surface="Asphalt", damage=0.0)
    r = _measure([(v1, 1.0), (None, 1.4)], 2.6, rate)
    check(abs(float(r.get("peak_torque", 0.0)) - 0.5) < 0.01
          and int(r.get("v1_packets", 0)) > 30, "alter_sender_wird_weiter_gelesen",
          f"v1 force=0.5 -> {float(r.get('peak_torque', 0.0)):.3f} "
          f"({int(r.get('v1_packets', 0))} Pakete)")

    # 3) Muell und aus dem Ruder gelaufene Werte: kein Absturz, harte Grenzen.
    junk = [(b"not json", 0.3), (b"\x00\x01\x02", 0.3),
            (_packet(v=2, torque=99.0, damper=5.0, friction=-2.0, rumble=-3.0,
                     rumble_hz=1000.0, pulse=9.0, pulse_dir=-9.0, source="Muell"), 0.6),
            (None, 1.2)]
    probe = _MagnitudeProbe()
    r = _measure(junk, 2.6, rate, probe)
    check(int(r.get("malformed", 0)) >= 2, "kaputte_pakete_werden_verworfen",
          f"{int(r.get('malformed', 0))} verworfen, "
          f"{int(r.get('packets', 0))} gelesen, kein Absturz")
    check(0.99 <= float(r.get("peak_wheel", 0.0)) <= 1.001
          and float(r.get("peak_damper", 0.0)) <= 1.001
          and float(r.get("peak_rumble", 0.0)) <= 1.001,
          "werte_werden_auf_die_grenzen_geklemmt",
          f"torque={float(r.get('peak_wheel', 0.0)):.3f} "
          f"damper={float(r.get('peak_damper', 0.0)):.3f} "
          f"rumble={float(r.get('peak_rumble', 0.0)):.3f}")

    # 4) Der Puls ist ein eigener Kanal und sitzt sofort auf der Kraft (die
    #    Rampe wird bewusst umgangen, sonst waere ein Schaltstoss kein Stoss).
    pul = _packet(v=2, torque=0.0, damper=0.0, friction=0.0, rumble=0.0,
                  rumble_hz=24.0, pulse=0.4, pulse_dir=1.0, spring=0.0,
                  gain=1.0, source="Schalten")
    probe = _MagnitudeProbe()
    r = _measure([(pul, 1.0), (None, 1.4)], 2.6, rate, probe)
    burst = float(r.get("peak_wheel", 0.0))
    check(abs(burst - 0.4 * PULSE_MIX) < 0.01, "puls_sitzt_sofort_auf_der_kraft",
          f"pulse=0.40 -> Rad {burst:.3f} = {burst / 0.4:.0%} des Pulses (ohne Rampe)")

    # 5) Gegenprobe zur Trennung der Kanaele: `torque` ist laut Protokoll die
    #    GRUNDKRAFT und enthaelt den Stoss NICHT. Ein Paket mit 0.4 Kraft plus
    #    Puls kommt deshalb als 0.4 + Puls an und nicht als 0.4 + 2 Pulse. Das
    #    Spiel haelt diese Trennung ein; geprueft wird sie dort, wo das Modell
    #    liegt (`godot_f1/tests/test_ffb_model.gd`,
    #    "einschlag_laesst_die_grundkraft_unveraendert").
    both = _packet(v=2, torque=0.4, damper=0.0, friction=0.0, rumble=0.0,
                   rumble_hz=24.0, pulse=0.4, pulse_dir=1.0, spring=0.0,
                   gain=1.0, source="Test")
    r = _measure([(both, 0.6), (None, 0.4)], 1.0, rate, _MagnitudeProbe())
    expected = 0.4 + 0.4 * PULSE_MIX
    peak = float(r.get("peak_wheel", 0.0))
    check(abs(peak - expected) < 0.01, "grundkraft_und_stoss_kommen_getrennt",
          f"torque 0.40 + pulse 0.40 -> {peak:.3f} (erwartet {expected:.3f})")

    # 6) `event` und `speed` waren die letzten blinden Passagiere im Paket:
    #    gesendet, aber vom Helfer nie gelesen. Wer am Lenkrad sitzt und sich
    #    fragt "was war das gerade", braucht genau diese zwei Zahlen.
    tagged = _packet(v=2, torque=0.30, damper=0.10, friction=0.10, rumble=0.0,
                     rumble_hz=24.0, pulse=0.3, pulse_dir=-1.0, spring=0.0,
                     gain=1.0, event="shift", speed=212.5, source="Asphalt",
                     clip=0.0, damage=0.0)
    r = _measure([(tagged, 0.5), (None, 0.3)], 0.9, rate, _MagnitudeProbe())
    got_speed = float(r.get("peak_speed", 0.0))
    check(r.get("last_event") == "shift" and abs(got_speed - 212.5) < 0.2,
          "ereignis_und_tempo_kommen_an",
          f"event={r.get('last_event')!r} Tempo {got_speed:.1f} km/h "
          f"(erwartet 'shift' / 212.5)")

    # 7) Der Auftrag nennt drei Raeder (G29/G920/G923). Ein fest auf "G29"
    #    gestellter Filter hat die anderen zwei nicht gefunden - dieselbe
    #    DirectInput-Arbeit, ein anderer Produktname, und der Helfer brach mit
    #    "kein Lenkrad gefunden" ab. Geprueft wird die Namensauswahl selbst,
    #    ohne Hardware: die drei echten Produktnamen muessen treffen, ein
    #    Gamepad und ein leerer Name nicht.
    family_hits = [
        ("G29", "Logitech G29 Driving Force Racing Wheel"),
        ("G920", "Logitech G920 Driving Force Racing Wheel"),
        ("G923", "Logitech G923 Racing Wheel for PC"),
    ]
    family_ok = all(wheel_name_matches(n, "", WHEEL_NAME_NEEDLES)
                    for n, _instance in family_hits)
    junk_ok = not wheel_name_matches("Xbox Wireless Controller") \
        and not wheel_name_matches("")
    own = wheel_name_needles("G923")
    own_ok = own == ("g923",) and wheel_name_matches(family_hits[2][1], "", own) \
        and not wheel_name_matches(family_hits[0][1], "", own)
    check(family_ok and junk_ok and own_ok,
          "die_ganze_lenkradfamilie_wird_gefunden",
          f"G29/G920/G923 = {family_ok}, Fremdgeraet ausgeschlossen = {junk_ok}, "
          f"--name G923 nur G923 = {own_ok} (Standard: "
          f"{'/'.join(n.upper() for n in WHEEL_NAME_NEEDLES)})")

    # 8) Rueckkanal: der Helfer antwortet dem Spiel. Daran haengt der
    #    HUD-Hinweis "KEIN HELFER" - und damit die einzige Moeglichkeit, von
    #    innen zu sehen, dass die Kraft gar keinen Empfaenger hat.
    ack_ok, ack_mode, ack_detail, _ack_msg = _ack_probe(rate)
    check(ack_ok and ack_mode == "dry", "der_helfer_antwortet_dem_spiel",
          f"Modus {ack_mode or '-'}: {ack_detail}")

    # 9) Das Lebenszeichen traegt die eigene Achsenstellung. Damit kann das
    #    Spiel die Kraftrichtung SELBST messen, ohne dass jemand das Rad mit
    #    Kraft drehen muss - genau der Punkt, der bis Welle 4 offen war.
    #    Ohne Rad (Trockenlauf) faellt das Feld weg; hier wird mit einem
    #    Ersatzrad gemessen, damit der Weg wirklich geprueft ist.
    axis_probe = _MagnitudeProbe()
    axis_probe.wheel.read_axis = lambda: 21234
    axis_ok, _axis_mode, axis_detail, axis_msg = _ack_probe(rate, wheel=axis_probe.wheel)
    check(axis_ok and axis_msg.get("axis") == 21234,
          "das_lebenszeichen_traegt_die_achsenstellung",
          f"axis={axis_msg.get('axis', None)} (erwartet 21234) - {axis_detail}")

    # Und die Gegenprobe: ohne Rad steht kein erfundener Wert im Paket.
    _dry_ok, _dry_mode, _dry_detail, dry_msg = _ack_probe(rate)
    check("axis" not in dry_msg, "ohne_rad_keine_erfundene_achse",
          f"Felder ohne Rad: {sorted(dry_msg.keys())}")

    print(f"FFB_CHECK {'PASS' if failed == 0 else 'FAIL'} {checks} Pruefungen, "
          f"{failed} Mangel")
    return 1 if failed else 0


## Der Fuehltest: die Stationen, die das Spiel am Lenkrad erzeugt, ohne Spiel.
##
## Jede Zeile ist eine Fahrsituation aus docs/FFB_F1_STYLE_PLAN.md, mit genau
## den Zahlen, die `ffb_model.gd` dort auch liefert. Wer das laufen laesst,
## fuehlt den Plan am eigenen Lenkrad - und kann sagen, welche Station zu
## schwach oder zu stark ist.
DEMO_STAGES = [
    (1.6, "Geradeaus, Schrittgeschwindigkeit: lose, nur Reibung",
     {"torque": 0.00, "damper": 0.12, "fric": 0.14, "rumble": 0.00, "rumble_hz": 20.0}),
    (2.0, "Geradeaus 250 km/h: Grundgewicht, kein Zappeln",
     {"torque": 0.00, "damper": 0.32, "fric": 0.10, "rumble": 0.06, "rumble_hz": 30.0}),
    (2.6, "Schneller Bogen, 3 g bei 250 km/h: schwer, drueckt zurueck",
     {"torque": -0.62, "damper": 0.30, "fric": 0.10, "rumble": 0.08, "rumble_hz": 30.0}),
    (2.6, "Vorderachse geht weg (Untersteuern): Lenkrad wird leicht",
     {"torque": -0.22, "damper": 0.30, "fric": 0.10, "rumble": 0.12, "rumble_hz": 32.0}),
    (2.0, "Kerb bei 120 km/h: hartes, schnelles Ruetteln",
     {"torque": -0.45, "damper": 0.25, "fric": 0.30, "rumble": 0.85, "rumble_hz": 38.0}),
    (2.0, "Kies: grobes Mahlen, langsamer als der Kerb",
     {"torque": -0.38, "damper": 0.22, "fric": 0.45, "rumble": 0.45, "rumble_hz": 12.0}),
    (2.0, "Vollbremsung, Vorderraeder blockieren: leicht + Rattern",
     {"torque": -0.12, "damper": 0.22, "fric": 0.16, "rumble": 0.60, "rumble_hz": 28.0}),
    (0.5, "Schaltstoss",
     {"torque": -0.30, "damper": 0.25, "fric": 0.12, "rumble": 0.05, "rumble_hz": 26.0,
      "pulse": 0.45, "pulse_dir": -1.0}),
    (0.5, "Einschlag in die Wand",
     {"torque": -0.20, "damper": 0.30, "fric": 0.20, "rumble": 0.30, "rumble_hz": 30.0,
      "pulse": 1.00, "pulse_dir": -1.0}),
    (1.6, "Loslassen",
     {"torque": 0.00, "damper": 0.06, "fric": 0.05, "rumble": 0.00, "rumble_hz": 20.0}),
]


def demo(rate: float, invert: bool, verbose: bool, exclusive: bool,
         gain: float, name_filter=None) -> int:
    """Fuehltest am echten Lenkrad, ohne das Spiel zu starten."""
    try:
        wheel = G29ForceFeedback(name_filter=name_filter, verbose=verbose,
                                 exclusive=exclusive)
    except WheelError as exc:
        print(f"DEMO FAIL: {exc}")
        return 1
    print(f"[demo] {wheel.name}")
    print(f"[demo] Effekte: {', '.join(wheel.effects_created) or '(keine)'}")
    if not wheel.effects_created:
        print("[demo] ohne Effekte gibt es nichts zu fuehlen - Ende")
        wheel.close()
        return 1
    print("[demo] Haende locker lassen: das Lenkrad bewegt sich von selbst.")
    period = 1.0 / max(rate, 20.0)
    live = {"torque": 0.0, "damper": 0.0, "fric": 0.0, "rumble": 0.0,
            "rumble_hz": 24.0, "pulse": 0.0, "pulse_dir": 0.0, "spring": 0.0}
    try:
        for seconds, label, stage in DEMO_STAGES:
            print(f"[demo] {label}  ({seconds:.1f} s)")
            target = dict(live)
            for key, value in stage.items():
                target[key] = value
            if "pulse" in stage:
                live["pulse"] = float(stage["pulse"])
                live["pulse_dir"] = float(stage.get("pulse_dir", -1.0))
            deadline = time.time() + seconds
            while time.time() < deadline:
                live["torque"] = _slew(live["torque"], float(target["torque"]), period)
                for key, tau in (("damper", 0.12), ("fric", 0.12),
                                 ("rumble", 0.05), ("rumble_hz", 0.10)):
                    live[key] = _approach(live[key], float(target[key]), period, tau)
                live["pulse"] = max(live["pulse"] - period / PULSE_DECAY, 0.0)
                wheel.apply(live["torque"], live["damper"], live["fric"],
                            live["rumble"], live["pulse"], invert, live["spring"],
                            live["rumble_hz"], gain, live["pulse_dir"])
                time.sleep(period)
    except KeyboardInterrupt:
        print("\n[demo] abgebrochen")
    finally:
        wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, invert)
        wheel.close()
    print("[demo] fertig - Kraft losgelassen")
    return 0


def sign_check(seconds: float, force: float, invert: bool, verbose: bool,
               exclusive: bool, name_filter=None) -> int:
    """Misst am echten Lenkrad, in welche Richtung eine positive Kraft dreht.

    Ohne diese Messung ist die Kraftrichtung geraten. Das Spiel kalibriert
    "rechts = +1"; hier wird nachgemessen, ob eine positive Kraft die Achse in
    dieselbe Richtung bewegt. Das Lenkrad muss dafuer losgelassen werden.
    """
    try:
        wheel = G29ForceFeedback(name_filter=name_filter, verbose=verbose,
                                 exclusive=exclusive)
    except WheelError as exc:
        print(f"SIGN FAIL: {exc}")
        return 1
    if not wheel.effects_created:
        print("SIGN FAIL: keine Effekte geladen")
        wheel.close()
        return 1

    def hold(value: float) -> None:
        deadline = time.time() + seconds
        while time.time() < deadline:
            wheel.apply(value, 0.05, 0.05, 0.0, 0.0, invert)
            time.sleep(0.02)

    rest = wheel.read_axis()
    hold(force)
    after_pos = wheel.read_axis()
    hold(-force)
    after_neg = wheel.read_axis()
    wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, invert)
    time.sleep(0.3)
    wheel.close()

    print(f"Achse ruhe      : {rest}")
    print(f"Achse +{force:+.2f} Kraft: {after_pos}")
    print(f"Achse -{force:+.2f} Kraft: {after_neg}")
    if rest is None or after_pos is None or after_neg is None:
        print("SIGN TEILWEISE: keine Achsendaten (Netzteil?) - Richtung unbekannt")
        return 2
    d_pos = after_pos - rest
    d_neg = after_neg - rest
    if d_pos == 0 and d_neg == 0:
        print("SIGN TEILWEISE: Achse bewegt sich nicht - Lenkrad festgehalten "
              "oder Kraft zu klein")
        return 2
    if d_pos > d_neg:
        print(f"SIGN PASS: positive Kraft dreht die Achse nach + "
              f"({d_pos:+d} vs {d_neg:+d}) - das ist dieselbe Richtung wie "
              f"'rechts = +1' im Spiel.")
        return 0
    print(f"SIGN ANDERS: positive Kraft dreht die Achse nach - "
          f"({d_pos:+d} vs {d_neg:+d}) - dann muss der Helfer mit --invert "
          f"laufen (oder das Spiel dreht das Vorzeichen).")
    return 3


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Logitech-Force-Feedback (G29/G920/G923) fuer Apex Circuit")
    default_port = int(os.environ.get("APEX_FFB_PORT", "5601") or 5601)
    parser.add_argument("--port", type=int, default=default_port,
                        help="UDP-Port, auf dem das Spiel sendet (Standard 5601, "
                             "oder die Umgebungsvariable APEX_FFB_PORT)")
    parser.add_argument("--rate", type=float, default=200.0,
                        help="Ansteuerungsrate in Hz (Standard 200)")
    parser.add_argument("--invert", action="store_true", help="Kraftrichtung umdrehen")
    parser.add_argument("--name", default=None, metavar="NAME",
                        help="Lenkrad suchen, dessen Name NAME enthaelt "
                             "(Standard: die ganze Familie G29/G920/G923; "
                             "mehrere mit Komma trennen)")
    # Das G29 nimmt Kraftbefehle nur an, wenn es exklusiv uebernommen ist
    # (sonst DIERR_NOTEXCLUSIVEACQUIRED beim Download). Deshalb ist exklusiv
    # die Voreinstellung; --shared schaltet es ab, wenn ein anderes Programm
    # das Lenkrad gleichzeitig lesen muss.
    parser.add_argument("--shared", dest="exclusive", action="store_false",
                        help="Lenkrad nicht exklusiv uebernehmen (Standard: exklusiv)")
    parser.set_defaults(exclusive=True)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--list", action="store_true", help="Geraete auflisten")
    parser.add_argument("--matrix", action="store_true",
                        help="Effekt-Varianten durchprobieren (Diagnose)")
    parser.add_argument("--selftest", action="store_true",
                        help="Geraet und Effekte pruefen, kurzen Teststoss geben")
    parser.add_argument("--selftest-seconds", type=float, default=1.2)
    parser.add_argument("--idle-release", type=float, default=0.5,
                        help="Sekunden ohne Paket, bis die Kraft faellt")
    parser.add_argument("--spring", type=float, default=0.0,
                        help="Zentrierfeder 0..1 (Standard 0: das Zentrieren "
                             "macht der Nachlauf des Spiels)")
    parser.add_argument("--gain", type=float, default=1.0,
                        help="manueller Trimm 0..1 auf alles, was ankommt "
                             "(Standard 1.0; die Staerke aus dem Spiel steckt "
                             "schon in der gesendeten Kraft)")
    parser.add_argument("--demo", action="store_true",
                        help="Fuehltest ohne Spiel: alle Stationen einmal "
                             "am echten Lenkrad abfahren")
    parser.add_argument("--sign-check", action="store_true",
                        help="messen, in welche Richtung eine positive Kraft dreht")
    parser.add_argument("--sign-seconds", type=float, default=0.6)
    parser.add_argument("--sign-force", type=float, default=0.25)
    parser.add_argument("--dry-run", action="store_true",
                        help="ohne Lenkrad rechnen: Pakete lesen, Rampe pruefen, "
                             "Wertebereiche ausgeben (Hardware-Check ohne Hardware)")
    parser.add_argument("--dry-run-seconds", type=float, default=8.0,
                        help="Laufzeit des Trockenlaufs (Standard 8 s)")
    parser.add_argument("--check", action="store_true",
                        help="Kette ohne Lenkrad PRUEFEN: Staerke genau einmal, "
                             "Rampe, Puls, kaputte Pakete, Kraft faellt am Ende "
                             "(Exit 0 = alles gut)")
    args = parser.parse_args(argv)
    if args.list:
        return list_devices()
    if args.matrix:
        try:
            wheel = G29ForceFeedback(name_filter=args.name, verbose=args.verbose,
                                     exclusive=args.exclusive)
        except WheelError as exc:
            print(f"MATRIX FAIL: {exc}")
            return 1
        wheel.matrix()
        wheel.close()
        return 0
    if args.selftest:
        return selftest(args.selftest_seconds, args.invert, args.verbose,
                        args.exclusive, args.name)
    if args.sign_check:
        return sign_check(args.sign_seconds, args.sign_force, args.invert,
                          args.verbose, args.exclusive, args.name)
    if args.check:
        return check_chain(args.rate)
    if args.demo:
        return demo(args.rate, args.invert, args.verbose, args.exclusive,
                    args.gain, args.name)
    return run_bridge(args.port, args.rate, args.invert, args.verbose,
                      args.idle_release, args.exclusive, args.spring, args.gain,
                      args.dry_run, args.dry_run_seconds if args.dry_run else 0.0,
                      name_filter=args.name)


if __name__ == "__main__":
    sys.exit(main())
