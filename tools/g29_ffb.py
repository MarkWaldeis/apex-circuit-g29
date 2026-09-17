"""Echtes Force Feedback fuer das Logitech G29 (DirectInput, ohne Zusatzpakete).

Warum es dieses Programm gibt
-----------------------------
Godot 4 hat keine Force-Feedback-Schnittstelle, und das G29 hat keine
Rumble-Motoren, auf die `Input.start_joy_vibration` wirken koennte. Das Spiel
kann die Kraft also nicht selbst erzeugen. Der G29 haengt aber als
DirectInput-Geraet am PC, und DirectInput kann sehr wohl Kraftbefehle an das
Lenkrad schicken. Genau das macht dieses Programm: es liest die Fahrzeugwerte,
die das Spiel per UDP schickt, und uebersetzt sie in echte Kraefte am Lenkrad.

Protokoll (vom Spiel gesendet, UTF-8 JSON, ein Objekt pro Paket):

    {"v":1,"force":0.0,"damp":0.0,"fric":0.0,"rumble":0.0,"pulse":0.0,
     "event":"shift","speed":42.5,"surface":"Asphalt","damage":0.0}

    force   -1.0 .. +1.0  Grundkraft (Zentrierung, Untersteuern, Aufprall)
    damp     0.0 ..  1.0  geschwindigkeitsabhaengige Daempfung
    fric     0.0 ..  1.0  Reibung (Kerb, Kies, Gras)
    rumble   0.0 ..  1.0  Ruetteln (Kerb, Ausritt)
    pulse    0.0 ..  1.0  einmaliger Stoss (Schalten, Aufprall)

Standardmaessig hoert das Programm auf 127.0.0.1:5601. Kommt 0,5 s lang kein
Paket (Spiel beendet, Menue), fallen die Kraefte zurueck, damit das Lenkrad
nicht gegen einen alten Befehl drueckt.

Aufrufe
-------
    python tools/g29_ffb.py                 # normaler Betrieb
    python tools/g29_ffb.py --selftest      # Geraet pruefen, Effekte laden, kurz Kraft geben
    python tools/g29_ffb.py --list          # zeigen, welche Lenkraeder DirectInput sieht
    python tools/g29_ffb.py --invert        # Kraftrichtung umdrehen

Das G29 braucht sein Netzteil: ohne Netzteil meldet es sich an, liefert aber
keine Achsendaten und kann auch keine Kraft erzeugen. `--selftest` sagt das
ausdruecklich, statt Erfolg vorzutaeuschen.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import socket
import sys
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


class G29ForceFeedback:
    """Oeffnet das G29 ueber DirectInput und haelt die vier Effekte."""

    def __init__(self, name_filter: str = "G29", verbose: bool = False,
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

    def _open_device(self, name_filter: str) -> None:
        """Geraet im Enum-Callback erzeugen.

        CreateDevice MUSS hier drin passieren: die Instanz-GUID eines
        DirectInput-Geraets ist nur waehrend der Aufzaehlung gueltig. Wird sie
        gespeichert und danach benutzt, antwortet Windows mit
        DIERR_DEVICENOTREG (0x80040154) - genau der Fehler, der hier zuerst
        auftrat.
        """
        callback_type = ctypes.WINFUNCTYPE(
            wintypes.BOOL, ctypes.POINTER(DIDEVICEINSTANCEW), ctypes.c_void_p)
        needle = name_filter.lower()
        seen: list[str] = []
        found: list[str] = []
        create = _method(self.dinput, 3, HRESULT, ctypes.POINTER(GUID),
                         ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p)

        def _cb(inst_ptr, _ref):
            inst = inst_ptr.contents
            product = inst.tszProductName
            seen.append(product)
            if needle not in f"{product} {inst.tszInstanceName}".lower():
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
                f"kein Lenkrad gefunden, dessen Name '{name_filter}' enthaelt "
                f"(DirectInput sieht: {', '.join(seen) or 'nichts'})")
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
              pulse: float, invert: bool = False, spring: float = 0.35) -> None:
        sign = -1.0 if invert else 1.0
        magnitude = int(max(-1.0, min(1.0, force)) * 10000 * sign)
        burst = int(max(0.0, min(1.0, pulse)) * 7000 * sign)
        if abs(burst) > abs(magnitude):
            magnitude += burst
        magnitude = int(max(-10000, min(10000, magnitude)))
        self._set_constant(magnitude)
        self._set_damper(int(max(0.0, min(1.0, damp)) * 7000))
        self._set_friction(int(max(0.0, min(1.0, fric)) * 7000))
        self._set_spring(int(max(0.0, min(1.0, spring)) * 9000))
        self._set_rumble(int(max(0.0, min(1.0, rumble)) * 8000))

    def _set_constant(self, magnitude: int) -> None:
        if not self.eff_constant:
            return
        self._constant.lMagnitude = magnitude
        self._update(self.eff_constant, self._constant)

    def _set_damper(self, coefficient: int) -> None:
        if not self.eff_damper:
            return
        self._damper.lPositiveCoefficient = coefficient
        self._damper.lNegativeCoefficient = -coefficient
        self._update(self.eff_damper, self._damper)

    def _set_friction(self, coefficient: int) -> None:
        if not self.eff_friction:
            return
        self._friction.lPositiveCoefficient = coefficient
        self._friction.lNegativeCoefficient = -coefficient
        self._update(self.eff_friction, self._friction)

    def _set_rumble(self, magnitude: int) -> None:
        if not self.eff_rumble:
            return
        self._periodic.dwMagnitude = magnitude
        self._update(self.eff_rumble, self._periodic)

    def _set_spring(self, coefficient: int) -> None:
        if not self.eff_spring:
            return
        self._spring.lOffset = 0
        self._spring.lPositiveCoefficient = coefficient
        self._spring.lNegativeCoefficient = -coefficient
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
             exclusive: bool = True) -> int:
    try:
        wheel = G29ForceFeedback(verbose=verbose, exclusive=exclusive)
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
               spring: float = 0.35) -> int:
    try:
        wheel = G29ForceFeedback(verbose=verbose, exclusive=exclusive)
    except WheelError as exc:
        print(f"[ffb] kein Lenkrad: {exc}")
        return 1
    print(f"[ffb] {wheel.name} bereit, Effekte: "
          f"{', '.join(wheel.effects_created) or '(keine)'}")
    if wheel.effects_failed:
        print(f"[ffb] nicht verfuegbar: {'; '.join(wheel.effects_failed)}")
    if not wheel.effects_created:
        print("[ffb] ohne Effekte beendet sich der Helfer")
        wheel.close()
        return 1

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.setblocking(False)

    period = 1.0 / max(rate, 20.0)
    state = {"force": 0.0, "damp": 0.0, "fric": 0.0, "rumble": 0.0, "pulse": 0.0}
    last_packet = 0.0
    pulse_until = 0.0
    packets = 0
    last_report = time.time()
    print(f"[ffb] hoert auf 127.0.0.1:{port} ({rate:.0f} Hz)")
    try:
        while True:
            now = time.time()
            got = None
            while True:
                try:
                    data, _ = sock.recvfrom(4096)
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
                    last_packet = now
                    for key in ("force", "damp", "fric", "rumble"):
                        try:
                            state[key] = float(msg.get(key, 0.0))
                        except (TypeError, ValueError):
                            state[key] = 0.0
                    try:
                        impulse = float(msg.get("pulse", 0.0))
                    except (TypeError, ValueError):
                        impulse = 0.0
                    if impulse > 0.02:
                        state["pulse"] = max(state["pulse"], impulse)
                        pulse_until = now + 0.10

            stale = (now - last_packet) > idle_release
            if stale:
                # Kein Spiel (mehr) am anderen Ende: Lenkrad loslassen.
                wheel.apply(0.0, 0.10, 0.05, 0.0, 0.0, invert, spring=0.12)
            else:
                if now > pulse_until:
                    state["pulse"] = max(0.0, state["pulse"] - 4.0 * period)
                wheel.apply(state["force"], state["damp"], state["fric"],
                            state["rumble"], state["pulse"], invert, spring)

            if verbose and now - last_report > 2.0:
                last_report = now
                print(f"[ffb] {packets} Pakete, force={state['force']:+.2f} "
                      f"rumble={state['rumble']:.2f} pulse={state['pulse']:.2f}"
                      + (" [idle]" if stale else ""))
            time.sleep(period)
    except KeyboardInterrupt:
        print("\n[ffb] beendet")
    finally:
        wheel.apply(0.0, 0.0, 0.0, 0.0, 0.0, invert)
        wheel.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Logitech-G29-Force-Feedback fuer Apex Circuit")
    parser.add_argument("--port", type=int, default=5601,
                        help="UDP-Port, auf dem das Spiel sendet (Standard 5601)")
    parser.add_argument("--rate", type=float, default=200.0,
                        help="Ansteuerungsrate in Hz (Standard 200)")
    parser.add_argument("--invert", action="store_true", help="Kraftrichtung umdrehen")
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
    parser.add_argument("--spring", type=float, default=0.35,
                        help="Zentrierfeder 0..1 (Standard 0.35)")
    args = parser.parse_args(argv)
    if args.list:
        return list_devices()
    if args.matrix:
        try:
            wheel = G29ForceFeedback(verbose=args.verbose, exclusive=args.exclusive)
        except WheelError as exc:
            print(f"MATRIX FAIL: {exc}")
            return 1
        wheel.matrix()
        wheel.close()
        return 0
    if args.selftest:
        return selftest(args.selftest_seconds, args.invert, args.verbose,
                        args.exclusive)
    return run_bridge(args.port, args.rate, args.invert, args.verbose,
                      args.idle_release, args.exclusive, args.spring)


if __name__ == "__main__":
    sys.exit(main())
