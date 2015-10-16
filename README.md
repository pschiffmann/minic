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


Usage
=====

(not implemented yet)
  1. Run `pub get`
  2. Run `pub serve`
  3. Open [http://localhost:8080]()


Limitations
===========

The package was never designed with the goal to implement the full C language spec, achieve high optimization, or a good runtime performance.
Specifically, you will miss the following features:
  * No preprocessor
  * No optimization!
    Every instruction is translated as written in the source code.
    No inlining, dead branch elimination, tail call elimination, ...
  * No standard library – the only available builtin functions are `malloc`, `free` and `printf`
  * No `register`, `volatile` and keywords from C99 or later specs


Implementation
==============

This paragraph focuses on the internal architecture of this software.
Reading it will be helpful if you want to understand how the code works, but is otherwise unimportant.

The implementation code is located in `lib/src/`.
All `.dart` files are relative to that directory, unless stated otherwise.
Whereever possible, language syntax and semantics are are defined declaratively.
These language declarations, including token types and pattern, operators, and C language builtins, are gathered in `language.dart`.

Our target architecture is an abstract C machine.
This machine works on 64 bit instructions with 3 operands that are all memory addresses.
Because our goal is to demonstrate memory usage in the C language and it would distract more than help, we omit registers completely.


Step 0: Tokenization
--------------------
[Tokenization](https://en.wikipedia.org/wiki/Tokenization_(lexical_analysis)) describes the process of splitting a source code string into tokens.
`token.dart` defines `Token` and `TokenIterator classes for that purpose.
The entry point to tokenization is the TokenIterator constructor.

Step 1: Parsing
---------------
In this step, we parse a list of tokens into an [AST](https://en.wikipedia.org/wiki/Abstract_syntax_tree).
The process is initiated with a call to `Parser::parse()` that returns a `Scope` object representing the global scope.

Nodes in our AST can be instances of these classes:
  * `Definition`s are language constructs that introduce a name into a scope.
    This includes variables, functions and types, each of which are implemented as a subclass of Definition.
    All classes are implemented in `scope.dart`.
  * A `Scope` serves as a container for definitions and is used to look up names.
    They are used for both block scopes and the global scope.
  * Everything that is not a type or function definition is a [statement](http://en.cppreference.com/w/c/language/statements).
    Again, every type of statement is represented as a separate class inheriting from `Statement`.
  * Expression statements contain a single `Expression` object.
    Expressions are parsed with a Pratt parser approach.
    Read this [excellent article](http://journal.stuffwithstuff.com/2011/03/19/pratt-parsers-expression-parsing-made-easy/) to learn more about how it works.
    The entry point to expression parsing is the `Parser::parseExpression()` method, and the parselets and Expression classes can be found in `expression.dart`.

************
Everything below this line is still TODO.
The text is just a concept how it could be implemented.
************

Step 1.5: Validation
--------------------
When an expression is built, it needs to be validated.
We need to check whether
  * used operands fulfill lvalue/rvalue and const requirements
  * referenced names exist in scope
  * `case` and `default` labels are only nested inside `switch` statements
  * the expression of `return` statements matches the function return type
  * function calls match a declared signature
This is done directly in the constructors of the Expression classes when the AST is built; hence this step is indexed as 1.5.

Step 2: Code generation
-----------------------
The `CMachineBackend`, defined in `backend.dart`, translates the AST into assembly instructions for our VM.

Step 3: "Linking"
-----------------
Because we don't support multiple source files or external libraries, this step only replaces `jmp` target placeholders by their address values.

Step 4: Execution
-----------------
Finally, the compilation result can be executed by the `VM` class, implemented in `cmachine.dart`.
VM objects store the virtual C memory, stack pointer, instruction pointer, etc.
Calling `execute()` executes the assigned instruction on the current data.
The VM also exposes a `rollback()` method to support limited undo/redo functionality in the UI.
To support this, the most recent instructions are stored internally as [commands](http://gameprogrammingpatterns.com/command.html).
