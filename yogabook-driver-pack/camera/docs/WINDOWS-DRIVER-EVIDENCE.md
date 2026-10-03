# Official Windows driver evidence

The inspected Lenovo package for the YB1-X91L contains exactly:

- `OV2740_CJAE533_CHT.cpf`;
- `ov2740.sys`, `.inf` and `.cat`;
- `iaisp64.sys`, `.inf` and `.cat`.

The INF files are UTF-16LE. `iaisp64.inf` identifies PCI device `8086:22b8` as
Intel Imaging Signal Processor 2401 and reports driver version
`21.10586.6069.2007` dated 2016-03-02. `ov2740.inf` identifies
`ACPI\OVTI2740`, reports sensor-driver version `1.4.2.2` dated 2016-02-19 and
copies `OV2740_CJAE533_CHT.cpf` to both Windows system and SysWOW64 locations.

No user-mode AIQ DLL is present in this extracted package. The two `.sys` files
are PE32+ Windows kernel drivers and cannot be loaded by Linux. Their presence
proves the hardware/firmware association and register provenance, but not how
the complete Windows camera framework consumes the tuning file.

Exact hashes are retained in
[`metadata/lenovo-driver-manifest.sha256`](../metadata/lenovo-driver-manifest.sha256).
The corresponding binaries are intentionally not distributed.

This evidence narrows the next investigation to either:

1. the separate Windows userspace component that loads CPF/AIQB data;
2. a compatible source-available Intel camera HAL/AIQ implementation; or
3. an open replacement pipeline using standard sensor controls and a software
   ISP, if the original AIQ ABI cannot be used legally and safely.
