# Flat-Combining

## Presentation Link: 
https://drive.google.com/file/d/1ptlZ6GApG8lGYM_h4yFxQOk7MHu4Cdgh/view?usp=sharing

## Overview
This repository contains an implementation and accompanying material related to *flat combining*.

## Required software

### OCaml toolchain (recommended via OPAM)
You need OCaml and common build tooling.

- **OCaml** (version depends on the repo; install via OPAM)
- **OPAM** (OCaml package manager)
- **dune** (build system), typically installed via OPAM

Install OPAM (see https://opam.ocaml.org/doc/Install.html), then:

```bash
opam init
opam switch create . ocaml-base-compiler.5.1.1
eval $(opam env)
opam install dune
```

> If your project uses additional OCaml libraries, install them with `opam install <pkg>` (or run the repo’s documented setup step if present).

### Python (optional, if you use the scripts)
Some repositories include helper scripts (plotting, benchmarking, data processing).

- **Python 3.10+** recommended
- Optional: `pip` / `venv`

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt  # only if this file exists
```

### LaTeX (optional, to build PDFs)
If you want to build the TeX documents, install a TeX distribution:

- **TeX Live** (Linux) / **MacTeX** (macOS) / **MiKTeX** (Windows)

Example (Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y texlive-full
```

## How to run / build

### Build the OCaml project (dune)
From the repository root:

```bash
dune build
```

To build a specific target (if applicable):

```bash
dune build @all
```

### Run an executable (if the repo defines one)
List available executables (common approaches):

```bash
dune exec --help
```

If you know the executable name (example):

```bash
dune exec ./path/to/exe.exe
```

### Run tests (if present)
```bash
dune runtest
```

## Building the LaTeX documents (optional)
From the directory containing the `.tex` file:

```bash
latexmk -pdf main.tex
```

Or (if `latexmk` is not available):

```bash
pdflatex main.tex
pdflatex main.tex
```

## Notes / troubleshooting

- If `dune` is not found, ensure your OPAM environment is loaded:
  ```bash
  eval $(opam env)
  ```
- If the repo uses a different OCaml version, change the OPAM switch line accordingly:
  ```bash
  opam switch create . ocaml-base-compiler.<version>
  ```

## License
See the repository for license information.
