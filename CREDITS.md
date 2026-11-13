# Credits & Acknowledgments

The development of **JioSTB-sideload** builds directly upon the reverse engineering breakthroughs, vulnerability discoveries, and tool consolidation accomplished by the open-source Android reverse-engineering community.

---

### Core Research & Exploit Contributors

- **Vishal Beniwal** ([Reddit: `u/ilikechocopies`](https://www.reddit.com/user/ilikechocopies) | [Instagram: `@soloxsurfer`](https://instagram.com/soloxsurfer))
  - Author and maintainer of the upstream [sideload-jiostb](https://github.com/ilikechocopies/sideload-jiostb) repository.
  - Streamlined the interactive Stage 1 pipeline, wrote comprehensive beginner-friendly documentation, and created diagnostic tooling (`doctor.py`).

- **Bihaan Sen & ak_0o7**
  - Original discovery of the TR-069 CWMP management spoofing vulnerability (`acs.oss.jio.com`) and AES-128 network-check gate bypass.
  - Creators of the original [Housekeeping-PoC](https://github.com/JFC-Group/Housekeeping-PoC) repository.

- **Otus9051**
  - Tool consolidation, initial Python TLS proxy (`pass_front.py`), and reverse proxy architecture.

- **Pavit Chhabra** ([Twitter: `@mesosan16`](https://twitter.com/mesosan16))
  - Discovery of the JHS-series (JHSC200 / JHSB200 / JioOS 2.0) trust store architecture and eMudhra compromised intermediate CA key recovery (`d = 156`).
  - Author of `forge_emudhra_chain.py` and discovery of the `/system/bin/tr069native` UID 0 on-boot CLU command injection hook.

---

### Upstream References

- [ilikechocopies/sideload-jiostb](https://github.com/ilikechocopies/sideload-jiostb)
- [JFC-Group/Housekeeping-PoC](https://github.com/JFC-Group/Housekeeping-PoC)
- [GenieACS Community Engine](https://genieacs.com)
