# PSP Reference Implementation (v1.0)

This repository provides a **reference implementation** of the
**Probabilistic Settlement Protocol (PSP) v1.0**.

It is intended for:
- Education and protocol understanding
- Local testing and developer experimentation
- Serving as a baseline for integrators and auditors

---

## Important Notice

This repository is **NOT**:
- The PSP protocol specification
- A production-ready deployment
- A canonical mainnet implementation
- A consumer-facing application

The authoritative protocol definition lives in the **PSP specification repository**:
- Whitepaper v1.0
- Roadmap
- v1.1 draft specification
- Compliance checklist

(See the companion specification repository for canonical documents.)

---

## Scope

This reference implementation focuses on:
- Outcome distribution rule registration
- Verifiable commit–reveal randomness flow
- Deterministic outcome selection and recomputation
- Invocation finalization and public auditability
- Deterministic protocol fee computation (with fee cap)
- Timelocked governance for fee parameter updates

It intentionally does **not** implement:
- Asset transfers or custody
- Dispute resolution
- Application-specific workflows (e-commerce, listing, etc.)
- Canonical deployments

---

## Repository Structure (Planned)

- `contracts/` — Solidity reference contracts
- `scripts/` — local deployment and demo scripts
- `test/` — deterministic recomputation tests
- `docs/` — implementation notes and rationale

---

## Versioning

- Protocol target: **PSP v1.0**
- Compatibility: **Reference only**
- Canonical deployments: **not included**

---

## License

License will be added in a subsequent commit.
