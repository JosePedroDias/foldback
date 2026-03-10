# lsp-client

A CLI tool that queries an [alive-lsp](https://github.com/nobody-famous/alive-lsp) Common Lisp language server over TCP. Used by the `/lsp` Claude Code skill to give Claude access to Lisp code intelligence (hover, go-to-definition, completion, eval, macro expansion, etc.).

## Prerequisites

### Install alive-lsp

```sh
git clone https://github.com/nobody-famous/alive-lsp.git
mv alive-lsp/ ~/quicklisp/local-projects/
```

### Build the client

```sh
cd tools/lsp-client && go build -o lsp-client .
```

Or simply run `make alive-lsp` which builds the client and starts the server.

## Usage

Start the alive-lsp TCP server (port 4006):

```sh
make alive-lsp
```

Then query it directly:

```sh
./tools/lsp-client/lsp-client -op documentSymbol -file src/state.lisp
./tools/lsp-client/lsp-client -op hover -file src/state.lisp -line 3 -char 8
./tools/lsp-client/lsp-client -op eval -text '(+ 1 2)'
./tools/lsp-client/lsp-client -op listPackages
```

Or use the `/lsp` skill inside Claude Code:

```
/lsp documentSymbol src/state.lisp
/lsp hover src/state.lisp line 3 char 8
/lsp eval (+ 1 2)
```

## Supported operations

### Standard LSP (require `-file`, position ops also need `-line -char`)

| Operation | Description |
|-----------|-------------|
| `documentSymbol` | List all symbols in a file |
| `hover` | Hover info (docs, types) |
| `definition` | Go to definition |
| `references` | Find all references |
| `completion` | Completions at cursor |
| `signatureHelp` | Signature help |
| `selectionRange` | Selection range |
| `semanticTokens` | Semantic tokens |
| `rangeFormatting` | Format range (also needs `-end-line -end-char`) |

### Custom alive-lsp operations

| Operation | Description | Flags |
|-----------|-------------|-------|
| `eval` | Evaluate Lisp expression | `-text`, optional `-pkg` |
| `macroexpand` | Full macro expansion | `-text`, optional `-pkg` |
| `macroexpand1` | Single-step expansion | `-text`, optional `-pkg` |
| `listPackages` | List all packages | (none) |
| `listAsdfSystems` | List ASDF systems | (none) |
| `loadAsdfSystem` | Load an ASDF system | `-name` |
| `compile` | Compile a file | `-file` |
| `loadFile` | Load a file | `-file` |
| `tryCompile` | Try-compile a file | `-file` |
| `symbol` | Symbol info at position | `-file -line -char` |
| `topFormBounds` | Top-level form bounds | `-file -line -char` |
| `surroundingFormBounds` | Surrounding form bounds | `-file -line -char` |
| `packageForPosition` | Package at position | `-file -line -char` |
| `inspect` | Inspect expression | `-text`, optional `-pkg` |
| `inspectSymbol` | Inspect a symbol | `-pkg -symbol` |
