// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_arbiter.h for the primary calling header

#include "Vahb_arbiter__pch.h"

void Vahb_arbiter___024root___ctor_var_reset(Vahb_arbiter___024root* vlSelf);

Vahb_arbiter___024root::Vahb_arbiter___024root(Vahb_arbiter__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vahb_arbiter___024root___ctor_var_reset(this);
}

void Vahb_arbiter___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vahb_arbiter___024root::~Vahb_arbiter___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
