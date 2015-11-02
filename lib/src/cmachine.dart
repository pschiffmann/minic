library minic.src.cmachine;

import 'dart:typed_data';

/// Instruction set of the virtual C machine.
///
/// Documentation for the individual instruction codes is parsed by a
/// transformer and used in the application as help texts.
enum InstructionCode {
  /// Load const
  /// ==========
  ///
  /// **loadc** _value_
  ///
  /// Load immediate _value_ on the stack.
  ///
  /// ```
  /// SP--; S[SP] ← _value_;
  /// ```
  loadc,

  /// Load address referenced by current stack element
  /// ================================================
  ///
  /// **load** _size_
  ///
  /// Load _size_ bytes on the stack, beginning from the address referenced by
  /// the current stack value.
  ///
  /// ```
  /// S[SP + 1]..S[SP + _size_ - 2] ← S[S[SP + 1]..S[SP]]..S[S[SP + 1]..S[SP] - ];
  /// ```
  load,

  /// Load from address
  /// =================
  ///
  /// **loada** _q_ _m_
  ///
  /// loadc q, load m
  loada,

  /// Load from constant address relative to frame pointer
  /// ====================================================
  ///
  /// **loadrc** _j_ _m_
  ///
  /// Load a value from address _j_ relative to the current frame pointer.
  ///
  /// SP++; S[SP] ← FP + j;
  loadrc,

  /// **loadmc** _q_
  ///
  /// loadrc −3, loadc q, add
  loadmc,

  /// **loadm** _q_ _m_
  ///
  /// loadmc q, load m
  loadm,

  /// **loadv** _b_
  ///
  /// S[SP +1] ← S[S[S[SP −2]]+b]; SP++;
  loadv,

  /// **loadsc** _q_
  ///
  /// S[SP +1] ← SP −q; SP ++;
  loadsc,

  /// **loads** _q_
  ///
  /// loadsc q, load
  loads,

  /// **pop** _m_
  ///
  /// SP ← SP−m;
  pop,

  /// **store** _m_
  ///
  /// ```
  /// for
  ///   i ← 0;
  ///   i < m;
  ///   i++
  /// do
  ///   S[S[SP]+i] ← S[SP−m+i];
  ///   SP−−;
  /// ```
  store,

  /// **storea** _q_ _m_
  ///
  /// loadc q, store m
  storea,

  /// **storer** _j_ _m_
  ///
  /// loadrc j, store m
  storer,

  /// **storem** _q_ _m_
  ///
  /// loadmc q, store m
  storem,

  /// **jump** _a_
  ///
  /// PC <- _a_
  jump,

  /// **jumpz** _a_
  ///
  /// if S[SP] = 0 then PC ← A; SP−−;
  jumpz,

  /// **jumpi**
  ///
  /// PC ← B + S[SP]; SP−−;
  jumpi,

  /// **add**
  ///
  /// S[SP − 1] ← S[SP − 1] + S[SP]; SP--;
  add,

  /// **sub**
  ///
  /// S[SP − 1] ← S[SP − 1] - S[SP]; SP--;
  sub,

  /// **mul**
  ///
  /// S[SP − 1] ← S[SP − 1] * S[SP]; SP--;
  mul,

  /// **div**
  ///
  /// S[SP − 1] ← S[SP − 1] / S[SP]; SP--;
  div,

  /// **mod**
  ///
  /// S[SP − 1] ← S[SP − 1] % S[SP]; SP--;
  mod,

  /// **neg**
  ///
  /// S[SP] ← -S[SP]
  neg,

  /// **eq**
  ///
  /// S[SP − 1] ← S[SP − 1] == S[SP]; SP--;
  eq,

  /// *neq**
  ///
  /// S[SP − 1] ← S[SP − 1] != S[SP]; SP--;
  neq,

  /// **lt**
  ///
  /// S[SP − 1] ← S[SP − 1] < S[SP]; SP--;
  lt,

  /// **le**
  ///
  /// S[SP − 1] ← S[SP − 1] <= S[SP]; SP--;
  le,

  /// **gt**
  ///
  /// S[SP − 1] ← S[SP − 1] > S[SP]; SP--;
  gt,

  /// **ge**
  ///
  /// S[SP − 1] ← S[SP − 1] >= S[SP]; SP--;
  ge,

  /// **and**
  ///
  /// S[SP − 1] ← S[SP − 1] & S[SP]; SP--;
  and,

  /// **or**
  ///
  /// S[SP − 1] ← S[SP − 1] | S[SP]; SP--;
  or,

  /// **not**
  ///
  /// S[SP − 1] ← S[SP − 1] ^ S[SP]; SP--;
  not,

  /// Save EP and FP
  /// ==============
  ///
  /// **mark**
  ///
  /// Store extreme pointer and frame pointer on the stack. This needs to be
  /// done before another function is called because the callee will override
  /// the values of those registers.
  ///
  /// S[SP+1] ← EP;
  /// S[SP+2] ← FP;
  /// SP ← SP+2;
  mark,

  /// **call**
  ///
  /// FP←SP; vartmp←PC; PC←S[SP]; S[SP]←tmp;
  call,

  /// **enter** _k_
  ///
  /// EP ← SP + k; if EP ≥ HP then error(„Stack Overflow“);
  enter,

  /// **alloc** _q_
  ///
  /// SP ← SP + q;
  alloc,

  /// **slide** _d_ z_
  ///
  /// if d>0thenif z=0thenSP ←SP−d;else{SP ←SP−d−z;
  /// fori←0;i<z;i++do{SP++; S[SP]←S[SP+d];}}
  slide,

  /// **ret**
  ///
  /// PC ← S[FP]; EP ← S[FP−2]; if EP≥HP then error("Stack Overflow"); SP ← FP−r; FP ← S[FP−1];
  ret,

  /// **new**
  ///
  /// if HP−S[SP]>EP then {HP←HP−S[SP]; S[SP]←HP;} else S[SP]←0;
  new_,

  /// **halt**
  halt
}

class VM {
  /// Combined stack and heap in a continous block of memory.
  ///
  /// The stack memory begins at `memory.size - 1` and grows towards zero, while
  /// the heap begins at zero and grows towards infinity.
  Uint8List memory;

  /// Points to the lowest currently used address of the stack (in [memory]).
  int stackPointer;

  /// Points to the highest currently used address of the heap (in [memory]).
  int framePointer;

  /// Points to the highest stack index the current function might allocate.
  int extremePointer;

  /// Stores the index into the program code of the next instruction.
  int programCounter;

  /// Execute [instruction] on the current data.
  ///
  /// An instruction is a 32-bit integer with the following sections, ordered
  /// from hsb to lsb:
  ///    ?? bit instruction code: Identifies the assembly instruction. The value
  ///           used is the respective index into [InstructionCode] left shifted
  ///           by 56.
  ///    ?? bit type hints: Only used to arithmetic instructions. Bits in this
  ///           byte are interpreted as flags. The first two bits indicate the
  ///           type (00: unsigned int, 01: signed int, 10: float), the next 3
  ///           bits store the operand size - 1 in bytes (for ints between 0 and
  ///           7, for floats either 3 or 7). The remaining 3 bits aren't used.
  ///   ?? bit operands: ...
  ///
  void execute(int instruction) {
    throw new UnimplementedError();
  }

  /// Take back the last executed instruction.
  ///
  /// Implementation note: use [command]
  /// (http://gameprogrammingpatterns.com/command.html) pattern internally.
  void rollback() {
    throw new UnimplementedError();
  }
}
