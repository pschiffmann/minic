# CAUTION: Work in Progress!
This project is currently on hold while I work on my [parser generator library]
(https://github.com/pschiffmann/dart-gardener), which I intend to use here.

Introduction
============

The minic package bundles a C compiler and an abstract C machine emulator as a web application.
It is implemented in [Dart](https://www.dartlang.org) and is intended to be used for teaching purposes.

When I talk to fellow students, I often notice that they have a hard time understanding the concept of variables in C:
That a variable is a label for a block of memory, rather than a value storage that exists in isolation from its environment.
I think that missing knowledge of this concept is the main cause of problems with pointer arithmetics, arrays, or call by reference.

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
