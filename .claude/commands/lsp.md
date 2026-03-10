Query the alive-lsp Common Lisp language server via TCP.

The server must be running (`make alive-lsp` in a separate terminal on port 4006).

Run the lsp-client binary at `tools/lsp-client/lsp-client` with the appropriate flags based on the user's request. If the binary doesn't exist, build it first with `cd tools/lsp-client && go build -o lsp-client .`

## User's request

$ARGUMENTS

## Available operations

### Standard LSP (require -file, position ops also need -line -char):

| Operation | Description | Flags |
|-----------|-------------|-------|
| `documentSymbol` | List all symbols in a file | `-file` |
| `hover` | Hover info (docs, types) | `-file -line -char` |
| `definition` | Go to definition | `-file -line -char` |
| `references` | Find all references | `-file -line -char` |
| `completion` | Completions at cursor | `-file -line -char` |
| `signatureHelp` | Signature help | `-file -line -char` |
| `selectionRange` | Selection range | `-file -line -char` |
| `semanticTokens` | Semantic tokens | `-file` |
| `rangeFormatting` | Format range | `-file -line -char -end-line -end-char` |

### Custom alive-lsp operations:

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

## Instructions

1. Parse the user's request to determine which operation(s) to run
2. Run the appropriate command using the Bash tool. Line and char are 1-based.
3. Present the results clearly

Example commands:
```
./tools/lsp-client/lsp-client -op documentSymbol -file src/state.lisp
./tools/lsp-client/lsp-client -op hover -file src/state.lisp -line 3 -char 8
./tools/lsp-client/lsp-client -op eval -text '(+ 1 2)'
./tools/lsp-client/lsp-client -op macroexpand -text '(defstruct point x y)'
./tools/lsp-client/lsp-client -op listPackages
```
