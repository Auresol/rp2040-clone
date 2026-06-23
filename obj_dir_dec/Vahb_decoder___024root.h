// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vahb_decoder.h for the primary calling header

#ifndef VERILATED_VAHB_DECODER___024ROOT_H_
#define VERILATED_VAHB_DECODER___024ROOT_H_  // guard

#include "verilated.h"


class Vahb_decoder__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vahb_decoder___024root final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(rst_n,0,0);
    VL_IN8(m_hwrite,0,0);
    VL_IN8(m_htrans,1,0);
    VL_IN8(m_hsize,2,0);
    VL_OUT8(m_hready,0,0);
    VL_OUT8(m_hresp,0,0);
    VL_OUT8(s0_hwrite,0,0);
    VL_OUT8(s0_htrans,1,0);
    VL_OUT8(s0_hsize,2,0);
    VL_IN8(s0_hready,0,0);
    VL_IN8(s0_hresp,0,0);
    VL_OUT8(s1_hwrite,0,0);
    VL_OUT8(s1_htrans,1,0);
    VL_OUT8(s1_hsize,2,0);
    VL_IN8(s1_hready,0,0);
    VL_IN8(s1_hresp,0,0);
    CData/*0:0*/ ahb_decoder__DOT__sel_r;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__rst_n__0;
    VL_IN(m_haddr,31,0);
    VL_IN(m_hwdata,31,0);
    VL_OUT(m_hrdata,31,0);
    VL_OUT(s0_haddr,31,0);
    VL_OUT(s0_hwdata,31,0);
    VL_IN(s0_hrdata,31,0);
    VL_OUT(s1_haddr,31,0);
    VL_OUT(s1_hwdata,31,0);
    VL_IN(s1_hrdata,31,0);
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vahb_decoder__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vahb_decoder___024root(Vahb_decoder__Syms* symsp, const char* namep);
    ~Vahb_decoder___024root();
    VL_UNCOPYABLE(Vahb_decoder___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
