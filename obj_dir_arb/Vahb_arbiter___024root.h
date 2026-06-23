// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vahb_arbiter.h for the primary calling header

#ifndef VERILATED_VAHB_ARBITER___024ROOT_H_
#define VERILATED_VAHB_ARBITER___024ROOT_H_  // guard

#include "verilated.h"


class Vahb_arbiter__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vahb_arbiter___024root final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(rst_n,0,0);
    VL_IN8(m0_hwrite,0,0);
    VL_IN8(m0_htrans,1,0);
    VL_IN8(m0_hsize,2,0);
    VL_IN8(m0_hburst,2,0);
    VL_IN8(m0_hprot,3,0);
    VL_IN8(m0_hmastlock,0,0);
    VL_IN8(m0_hmaster,7,0);
    VL_OUT8(m0_hready,0,0);
    VL_OUT8(m0_hresp,0,0);
    VL_IN8(m1_hwrite,0,0);
    VL_IN8(m1_htrans,1,0);
    VL_IN8(m1_hsize,2,0);
    VL_IN8(m1_hburst,2,0);
    VL_IN8(m1_hprot,3,0);
    VL_IN8(m1_hmastlock,0,0);
    VL_IN8(m1_hmaster,7,0);
    VL_OUT8(m1_hready,0,0);
    VL_OUT8(m1_hresp,0,0);
    VL_OUT8(s_hwrite,0,0);
    VL_OUT8(s_htrans,1,0);
    VL_OUT8(s_hsize,2,0);
    VL_OUT8(s_hburst,2,0);
    VL_OUT8(s_hprot,3,0);
    VL_OUT8(s_hmastlock,0,0);
    VL_OUT8(s_hmaster,7,0);
    VL_IN8(s_hready,0,0);
    VL_IN8(s_hresp,0,0);
    CData/*0:0*/ ahb_arbiter__DOT__grant;
    CData/*0:0*/ ahb_arbiter__DOT__busy;
    CData/*0:0*/ ahb_arbiter__DOT__arb_grant;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__rst_n__0;
    VL_IN(m0_haddr,31,0);
    VL_IN(m0_hwdata,31,0);
    VL_OUT(m0_hrdata,31,0);
    VL_IN(m1_haddr,31,0);
    VL_IN(m1_hwdata,31,0);
    VL_OUT(m1_hrdata,31,0);
    VL_OUT(s_haddr,31,0);
    VL_OUT(s_hwdata,31,0);
    VL_IN(s_hrdata,31,0);
    IData/*31:0*/ __VactIterCount;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vahb_arbiter__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vahb_arbiter___024root(Vahb_arbiter__Syms* symsp, const char* namep);
    ~Vahb_arbiter___024root();
    VL_UNCOPYABLE(Vahb_arbiter___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
