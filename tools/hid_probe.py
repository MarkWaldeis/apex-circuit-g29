"""Read raw HID input reports of a USB device (default: Logitech G29).

This separates "the wheel really sends nothing" from "the engine reads it
wrong": Windows' HID stack is queried directly through hid.dll/setupapi.dll,
without SDL, DirectInput or Godot in the way.

**A timeout here is not proof of a defect.** The G29 only sends a report when
something changes - whoever runs this without turning the wheel reads an idle
device and sees "report timeout ... (no data)" on a perfectly working wheel.
Measured on 21.09.2026: this script timed out on all three interfaces while
`python tools/hid_vs_dinput.py` (which drives the wheel with force first)
counted 1 920 reports on the *same* interface at the same time. The old
conclusion "no reports, so the power supply is missing" was therefore wrong;
what that day's silence really was is documented in
`docs/reviews/ffb_wave7_ownership.md`.

For a test that means something, use `tools/hid_vs_dinput.py`: it moves the
wheel and reads both paths - HID and DirectInput - at once.

Usage: python tools/hid_probe.py [vid_pid] [reports] [timeout_ms]
       python tools/hid_probe.py 046d:c24f
"""

import ctypes
import sys
import time
from ctypes import wintypes

setupapi = ctypes.WinDLL("setupapi")
hid = ctypes.WinDLL("hid")
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

HANDLE = wintypes.HANDLE
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

DIGCF_PRESENT = 0x02
DIGCF_DEVICEINTERFACE = 0x10
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
OPEN_EXISTING = 3
FILE_FLAG_OVERLAPPED = 0x40000000
WAIT_OBJECT_0 = 0
WAIT_TIMEOUT = 0x102


class GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD),
                ("Data3", wintypes.WORD), ("Data4", ctypes.c_ubyte * 8)]


class SP_DEVICE_INTERFACE_DATA(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("InterfaceClassGuid", GUID),
                ("Flags", wintypes.DWORD), ("Reserved", ctypes.POINTER(ctypes.c_ulong))]


class HIDD_ATTRIBUTES(ctypes.Structure):
    _fields_ = [("Size", ctypes.c_ulong), ("VendorID", ctypes.c_ushort),
                ("ProductID", ctypes.c_ushort), ("VersionNumber", ctypes.c_ushort)]


class HIDP_CAPS(ctypes.Structure):
    _fields_ = [("Usage", ctypes.c_ushort), ("UsagePage", ctypes.c_ushort),
                ("InputReportByteLength", ctypes.c_ushort),
                ("OutputReportByteLength", ctypes.c_ushort),
                ("FeatureReportByteLength", ctypes.c_ushort),
                ("Reserved", ctypes.c_ushort * 17),
                ("NumberLinkCollectionNodes", ctypes.c_ushort),
                ("NumberInputButtonCaps", ctypes.c_ushort),
                ("NumberInputValueCaps", ctypes.c_ushort),
                ("NumberInputDataIndices", ctypes.c_ushort),
                ("NumberOutputButtonCaps", ctypes.c_ushort),
                ("NumberOutputValueCaps", ctypes.c_ushort),
                ("NumberOutputDataIndices", ctypes.c_ushort),
                ("NumberFeatureButtonCaps", ctypes.c_ushort),
                ("NumberFeatureValueCaps", ctypes.c_ushort),
                ("NumberFeatureDataIndices", ctypes.c_ushort)]


class OVERLAPPED(ctypes.Structure):
    _fields_ = [("Internal", ctypes.c_void_p), ("InternalHigh", ctypes.c_void_p),
                ("Offset", wintypes.DWORD), ("OffsetHigh", wintypes.DWORD),
                ("hEvent", HANDLE)]


setupapi.SetupDiGetClassDevsW.restype = HANDLE
setupapi.SetupDiGetClassDevsW.argtypes = [ctypes.POINTER(GUID), wintypes.LPCWSTR,
                                         wintypes.HWND, wintypes.DWORD]
setupapi.SetupDiEnumDeviceInterfaces.restype = wintypes.BOOL
setupapi.SetupDiEnumDeviceInterfaces.argtypes = [HANDLE, ctypes.c_void_p,
                                                 ctypes.POINTER(GUID), wintypes.DWORD,
                                                 ctypes.POINTER(SP_DEVICE_INTERFACE_DATA)]
setupapi.SetupDiGetDeviceInterfaceDetailW.restype = wintypes.BOOL
setupapi.SetupDiGetDeviceInterfaceDetailW.argtypes = [
    HANDLE, ctypes.POINTER(SP_DEVICE_INTERFACE_DATA), ctypes.c_void_p, wintypes.DWORD,
    ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
hid.HidD_GetHidGuid.argtypes = [ctypes.POINTER(GUID)]
hid.HidD_GetAttributes.argtypes = [HANDLE, ctypes.POINTER(HIDD_ATTRIBUTES)]
hid.HidD_GetPreparsedData.argtypes = [HANDLE, ctypes.POINTER(ctypes.c_void_p)]
hid.HidP_GetCaps.argtypes = [ctypes.c_void_p, ctypes.POINTER(HIDP_CAPS)]
kernel32.CreateFileW.restype = HANDLE
kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                 ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, HANDLE]
kernel32.ReadFile.restype = wintypes.BOOL
kernel32.ReadFile.argtypes = [HANDLE, ctypes.c_void_p, wintypes.DWORD,
                              ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
kernel32.WaitForSingleObject.restype = wintypes.DWORD
kernel32.WaitForSingleObject.argtypes = [HANDLE, wintypes.DWORD]
kernel32.CreateEventW.restype = HANDLE
kernel32.CloseHandle.argtypes = [HANDLE]


def device_paths(vid: int, pid: int):
    guid = GUID()
    hid.HidD_GetHidGuid(ctypes.byref(guid))
    devs = setupapi.SetupDiGetClassDevsW(ctypes.byref(guid), None, None,
                                         DIGCF_PRESENT | DIGCF_DEVICEINTERFACE)
    if not devs or devs == INVALID_HANDLE_VALUE:
        print("SetupDiGetClassDevs failed err=", ctypes.get_last_error())
        return []
    out = []
    iface = SP_DEVICE_INTERFACE_DATA()
    iface.cbSize = ctypes.sizeof(iface)
    i = 0
    seen = 0
    while setupapi.SetupDiEnumDeviceInterfaces(devs, None, ctypes.byref(guid), i,
                                               ctypes.byref(iface)):
        seen += 1
        need = wintypes.DWORD(0)
        setupapi.SetupDiGetDeviceInterfaceDetailW(devs, ctypes.byref(iface), None, 0,
                                                  ctypes.byref(need), None)
        if need.value == 0:
            print("  detail size query failed err=", ctypes.get_last_error())
            i += 1
            continue
        buf = ctypes.create_string_buffer(need.value + 8)
        cb = 8 if ctypes.sizeof(ctypes.c_void_p) == 8 else 4
        ctypes.memmove(buf, ctypes.byref(ctypes.c_ulong(cb)), 4)
        if setupapi.SetupDiGetDeviceInterfaceDetailW(devs, ctypes.byref(iface), buf,
                                                     need.value, ctypes.byref(need), None):
            path = ctypes.wstring_at(ctypes.addressof(buf) + 4)
            if f"vid_{vid:04x}&pid_{pid:04x}" in path.lower():
                out.append(path)
        else:
            print("  detail failed err=", ctypes.get_last_error())
        i += 1
    if seen == 0:
        print("no HID interfaces enumerated at all, err=", ctypes.get_last_error())
    else:
        print("enumerated %d HID interfaces, %d match the requested vid/pid" % (seen, len(out)))
    return out


def read_reports(path: str, count: int, timeout_ms: int):
    handle = kernel32.CreateFileW(ctypes.c_wchar_p(path), GENERIC_READ | GENERIC_WRITE,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE, None, OPEN_EXISTING,
                                  FILE_FLAG_OVERLAPPED, None)
    if not handle or handle == INVALID_HANDLE_VALUE:
        print("  open failed err=", ctypes.get_last_error())
        return
    attrs = HIDD_ATTRIBUTES()
    attrs.Size = ctypes.sizeof(attrs)
    hid.HidD_GetAttributes(handle, ctypes.byref(attrs))
    pp = ctypes.c_void_p()
    if hid.HidD_GetPreparsedData(handle, ctypes.byref(pp)):
        caps = HIDP_CAPS()
        hid.HidP_GetCaps(pp, ctypes.byref(caps))
        print("  usage_page=0x%04x usage=0x%04x input_len=%d values=%d buttons=%d" % (
            caps.UsagePage, caps.Usage, caps.InputReportByteLength,
            caps.NumberInputValueCaps, caps.NumberInputButtonCaps))
        hid.HidD_FreePreparsedData(pp)
    size = max(caps.InputReportByteLength, 16)
    buf = ctypes.create_string_buffer(size)
    got = 0
    for _ in range(count):
        ov = OVERLAPPED()
        ov.hEvent = kernel32.CreateEventW(None, True, False, None)
        read = wintypes.DWORD(0)
        ok = kernel32.ReadFile(handle, buf, size, ctypes.byref(read), ctypes.byref(ov))
        if not ok:
            err = ctypes.get_last_error()
            if err == 997:  # ERROR_IO_PENDING
                rc = kernel32.WaitForSingleObject(ov.hEvent, timeout_ms)
                if rc == WAIT_TIMEOUT:
                    print("  report timeout after %d ms (no data)" % timeout_ms)
                    kernel32.CancelIo(handle)
                    continue
                kernel32.GetOverlappedResult(handle, ctypes.byref(ov), ctypes.byref(read), False)
            else:
                print("  read failed err=", err)
        kernel32.CloseHandle(ov.hEvent)
        data = bytes(buf.raw[:max(read.value, 0)])
        print("  report %d: %s" % (got, data.hex(" ")))
        got += 1
    kernel32.CloseHandle(handle)


def main():
    vp = sys.argv[1] if len(sys.argv) > 1 else "046d:c24f"
    reports = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    timeout = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
    vid, pid = (int(x, 16) for x in vp.split(":"))
    paths = device_paths(vid, pid)
    print(f"hid interfaces for {vid:04x}:{pid:04x} = {len(paths)}")
    for p in paths:
        print(p)
        read_reports(p, reports, timeout)
        time.sleep(0.1)


if __name__ == "__main__":
    main()
