// check-parens: reports unbalanced parentheses in Lisp source files.
// Aware of line comments (;) and strings ("...").
//
// Usage: go run scripts/check-parens.go src/games/airhockey.lisp [src/server.lisp ...]
package main

import (
	"fmt"
	"os"
	"strings"
)

func check(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
		return false
	}

	lines := strings.Split(string(data), "\n")
	depth := 0
	ok := true

	for lineNum, line := range lines {
		inString := false
		prevDepth := depth

		for i := 0; i < len(line); i++ {
			ch := line[i]

			if inString {
				if ch == '\\' {
					i++ // skip escaped char
				} else if ch == '"' {
					inString = false
				}
				continue
			}

			switch ch {
			case ';':
				goto nextLine // rest of line is comment
			case '"':
				inString = true
			case '(':
				depth++
			case ')':
				depth--
				if depth < 0 {
					fmt.Printf("%s:%d: extra ')' (depth went negative)\n", path, lineNum+1)
					ok = false
					depth = 0
				}
			}
		}
	nextLine:

		if depth != prevDepth {
			_ = prevDepth // available for verbose mode if needed
		}
	}

	if depth > 0 {
		fmt.Printf("%s: missing %d closing paren(s) at end of file\n", path, depth)

		// Second pass: find the last line where depth increased, to help locate the problem
		depth = 0
		lastIncreaseLine := 0
		for lineNum, line := range lines {
			inString := false
			prevDepth := depth

			for i := 0; i < len(line); i++ {
				ch := line[i]
				if inString {
					if ch == '\\' {
						i++
					} else if ch == '"' {
						inString = false
					}
					continue
				}
				switch ch {
				case ';':
					goto nextLine2
				case '"':
					inString = true
				case '(':
					depth++
				case ')':
					depth--
				}
			}
		nextLine2:

			if depth > prevDepth {
				lastIncreaseLine = lineNum + 1
			}
		}
		fmt.Printf("%s:%d: last line where depth increased (likely near the problem)\n", path, lastIncreaseLine)
		ok = false
	}

	if ok {
		fmt.Printf("%s: balanced\n", path)
	}
	return ok
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: go run scripts/check-parens.go <file.lisp> ...\n")
		os.Exit(1)
	}

	allOk := true
	for _, path := range os.Args[1:] {
		if !check(path) {
			allOk = false
		}
	}
	if !allOk {
		os.Exit(1)
	}
}
