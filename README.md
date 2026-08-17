# OrbifolderBridge

[![Build Status](https://github.com/xiupos/OrbifolderBridge.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/xiupos/OrbifolderBridge.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://xiupos.github.io/OrbifolderBridge.jl/dev/)

A Julia bridge to the C++ [`orbifolder`](https://orbifolder.hepforge.org/) and
[`nonSUSYorbifolder`](https://github.com/StringsIFUNAM/nonSUSYorbifolder) tools for
constructing and analyzing heterotic string orbifold compactifications, for use with
[OSCAR.jl](https://www.oscar-system.org/).

> **⚠ EXPERIMENTAL — NO MAINTENANCE GUARANTEE.** Not registered in the Julia General registry;
> expect breaking changes without notice. Do not depend on it in production code.

**See the [documentation](https://xiupos.github.io/OrbifolderBridge.jl/dev/) for installation
(you must build `orbifolder`/`nonSUSYorbifolder` yourself), usage, and the full API reference.**

## License

[MIT](LICENSE) for this bridge package. The upstream `orbifolder`/`nonSUSYorbifolder` tools
you build and run separately are licensed under the GPL — see their respective repositories.
