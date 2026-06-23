// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_decoder.h for the primary calling header

#include "Vahb_decoder__pch.h"

void Vahb_decoder___024root___ctor_var_reset(Vahb_decoder___024root* vlSelf);

Vahb_decoder___024root::Vahb_decoder___024root(Vahb_decoder__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    Vahb_decoder___024root___ctor_var_reset(this);
}

void Vahb_decoder___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vahb_decoder___024root::~Vahb_decoder___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
