// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VAHB_DECODER__SYMS_H_
#define VERILATED_VAHB_DECODER__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vahb_decoder.h"

// INCLUDE MODULE CLASSES
#include "Vahb_decoder___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vahb_decoder__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vahb_decoder* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vahb_decoder___024root         TOP;

    // CONSTRUCTORS
    Vahb_decoder__Syms(VerilatedContext* contextp, const char* namep, Vahb_decoder* modelp);
    ~Vahb_decoder__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
