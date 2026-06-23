// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VAHB_ARBITER__SYMS_H_
#define VERILATED_VAHB_ARBITER__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vahb_arbiter.h"

// INCLUDE MODULE CLASSES
#include "Vahb_arbiter___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vahb_arbiter__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vahb_arbiter* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vahb_arbiter___024root         TOP;

    // CONSTRUCTORS
    Vahb_arbiter__Syms(VerilatedContext* contextp, const char* namep, Vahb_arbiter* modelp);
    ~Vahb_arbiter__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
