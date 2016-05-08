# CAUTION: Work in Progress!
This document describes the desired result, not the current status of this project!

Introduction
============

The minic package bundles a C compiler and an abstract C machine emulator as a web application.
It is implemented in [Dart](https://www.dartlang.org) and is intended to be used for teaching purposes.

When I talk to fellow students, I often notice that they have a hard time understanding the concept of variables in C:
That a variable is a label for a block of memory, rather than a value storage that exists in isolation from its environment.
I think that missing knowledge of this concept is the main cause of problems with pointer arithmetics, arrays or call by reference.

However, explaining it turned out to be quite difficult for me:
I – and also the profs whose lectures I attended so far – draw memory stacks on the chalkboard and demonstrate how certain operations interact with it, but doing that by hand is both tedious and hard to follow.
From this last observation developed the idea to implement an interactive version of this chalkboard simulation, and well, here we are.

Limitations
===========

The package was never designed with the goal to implement the full C language spec, achieve high optimization, or a good runtime performance.
Specifically, you will miss the following features:
  * No preprocessor
  * No optimization!
    Every instruction is translated as written in the source code.
    No inlining, dead branch elimination, tail call elimination, ...
  * No standard library – the only available builtin functions are `malloc`, `free`, `printf` and `exit`.
  * No `register`, `volatile` and keywords from C99 or later specs

Internals
=========

Due to the limited feature set, the choice for an expressive and uncluttered language, and the attention devoted to documentation, I hope that this source code is understandable for outsiders in acceptable learning time.
For people like me, who like to learn programming concepts by example, this package might therefore serve as a gentle introduction to some of the basics of compiler building: lexing, parsing, and code generation.
If you want to go that way, or even want to contribute to the project, here is a very short overview of the relevant source files.

Compilation starts with _lexical analysis_, which splits the input string into a list of tokens;
this is implemented in `scanner.dart`.
Next is _parsing_, which builds these tokens into a syntax tree.
The nodes that make up this tree can be found in `ast.dart`, and the parser in `parser.dart`.
The last step in the compilation process is _code generation_, where a list of instructions is generated that implements the behaviour of the syntax tree on the VM architecture.
The respective code is `abstract_machine/code_generator.dart`.
Finally, the generated instructions are _executed_ on a virtual machine.
Both the VM and the instruction set that it supports are implemented in `abstract_machine/vm.dart`.

You can find more details on every step in the respective library documentation, which you can find at the top of every source file.
