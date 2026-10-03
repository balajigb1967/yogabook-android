# Attribution and provenance

Yoga Book Camera is an independent integration project for the Lenovo Yoga
Book YB1-X91L.

Hardware behavior and implementation research reference:

- the Linux kernel OV2740, OV8858, IPU bridge and AtomISP drivers, licensed
  under their respective upstream SPDX terms;
- the GPL-2.0 upstream Linux OV5670 manual-white-balance implementation; the
  corresponding Yoga Book OV8858 kernel change retains its exact
  `Copyright (c) 2017 Intel Corporation.` notice;
- Lenovo's official Yoga Book Windows driver package and its
  `OV2740_CJAE533_CHT.cpf` Intel AIQB tuning artifact;
- [`EasyNetDev/atomisp-6.10-dkms`](https://github.com/EasyNetDev/atomisp-6.10-dkms),
  an external-module packaging of older upstream AtomISP kernel sources;
- the AtomISP cleanup and sensor-integration work in upstream Linux;
- Hans de Goede's upstream historical `intel_atomisp2_pm` power-management
  driver, used to establish that it is a suspend-only shim rather than an
  image-processing implementation;
- physical YB1-X91L captures and diagnostics performed by the Yoga Book
  project.

No source from Lenovo's proprietary driver and no Lenovo/Intel tuning binary
is distributed by this repository. Lenovo and Intel product names are used
only to identify the compatible hardware and provenance of user-supplied
artifacts.
