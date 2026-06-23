// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_arbiter.h for the primary calling header

#include "Vahb_arbiter__pch.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vahb_arbiter___024root___eval_triggers__ico(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_triggers__ico\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VicoTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VicoFirstIteration)));
    vlSelfRef.__VicoFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vahb_arbiter___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
}

bool Vahb_arbiter___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vahb_arbiter___024root___ico_sequent__TOP__0(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___ico_sequent__TOP__0\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.m0_hrdata = vlSelfRef.s_hrdata;
    vlSelfRef.m1_hrdata = vlSelfRef.s_hrdata;
    vlSelfRef.m0_hresp = vlSelfRef.s_hresp;
    vlSelfRef.m1_hresp = vlSelfRef.s_hresp;
    vlSelfRef.ahb_arbiter__DOT__arb_grant = (1U & ((IData)(vlSelfRef.ahb_arbiter__DOT__busy)
                                                    ? (IData)(vlSelfRef.ahb_arbiter__DOT__grant)
                                                    : 
                                                   ((~ 
                                                     ((IData)(vlSelfRef.m0_htrans) 
                                                      >> 1U)) 
                                                    & ((IData)(vlSelfRef.m1_htrans) 
                                                       >> 1U))));
    vlSelfRef.m0_hready = ((~ (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)) 
                           & (IData)(vlSelfRef.s_hready));
    if (vlSelfRef.ahb_arbiter__DOT__arb_grant) {
        vlSelfRef.m1_hready = vlSelfRef.s_hready;
        vlSelfRef.s_haddr = vlSelfRef.m1_haddr;
        vlSelfRef.s_hwrite = vlSelfRef.m1_hwrite;
        vlSelfRef.s_htrans = vlSelfRef.m1_htrans;
        vlSelfRef.s_hsize = vlSelfRef.m1_hsize;
        vlSelfRef.s_hburst = vlSelfRef.m1_hburst;
        vlSelfRef.s_hprot = vlSelfRef.m1_hprot;
        vlSelfRef.s_hmastlock = vlSelfRef.m1_hmastlock;
        vlSelfRef.s_hmaster = vlSelfRef.m1_hmaster;
        vlSelfRef.s_hwdata = vlSelfRef.m1_hwdata;
    } else {
        vlSelfRef.m1_hready = 0U;
        vlSelfRef.s_haddr = vlSelfRef.m0_haddr;
        vlSelfRef.s_hwrite = vlSelfRef.m0_hwrite;
        vlSelfRef.s_htrans = vlSelfRef.m0_htrans;
        vlSelfRef.s_hsize = vlSelfRef.m0_hsize;
        vlSelfRef.s_hburst = vlSelfRef.m0_hburst;
        vlSelfRef.s_hprot = vlSelfRef.m0_hprot;
        vlSelfRef.s_hmastlock = vlSelfRef.m0_hmastlock;
        vlSelfRef.s_hmaster = vlSelfRef.m0_hmaster;
        vlSelfRef.s_hwdata = vlSelfRef.m0_hwdata;
    }
}

void Vahb_arbiter___024root___eval_ico(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_ico\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VicoTriggered[0U])) {
        vlSelfRef.m0_hrdata = vlSelfRef.s_hrdata;
        vlSelfRef.m1_hrdata = vlSelfRef.s_hrdata;
        vlSelfRef.m0_hresp = vlSelfRef.s_hresp;
        vlSelfRef.m1_hresp = vlSelfRef.s_hresp;
        vlSelfRef.ahb_arbiter__DOT__arb_grant = (1U 
                                                 & ((IData)(vlSelfRef.ahb_arbiter__DOT__busy)
                                                     ? (IData)(vlSelfRef.ahb_arbiter__DOT__grant)
                                                     : 
                                                    ((~ 
                                                      ((IData)(vlSelfRef.m0_htrans) 
                                                       >> 1U)) 
                                                     & ((IData)(vlSelfRef.m1_htrans) 
                                                        >> 1U))));
        vlSelfRef.m0_hready = ((~ (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)) 
                               & (IData)(vlSelfRef.s_hready));
        if (vlSelfRef.ahb_arbiter__DOT__arb_grant) {
            vlSelfRef.m1_hready = vlSelfRef.s_hready;
            vlSelfRef.s_haddr = vlSelfRef.m1_haddr;
            vlSelfRef.s_hwrite = vlSelfRef.m1_hwrite;
            vlSelfRef.s_htrans = vlSelfRef.m1_htrans;
            vlSelfRef.s_hsize = vlSelfRef.m1_hsize;
            vlSelfRef.s_hburst = vlSelfRef.m1_hburst;
            vlSelfRef.s_hprot = vlSelfRef.m1_hprot;
            vlSelfRef.s_hmastlock = vlSelfRef.m1_hmastlock;
            vlSelfRef.s_hmaster = vlSelfRef.m1_hmaster;
            vlSelfRef.s_hwdata = vlSelfRef.m1_hwdata;
        } else {
            vlSelfRef.m1_hready = 0U;
            vlSelfRef.s_haddr = vlSelfRef.m0_haddr;
            vlSelfRef.s_hwrite = vlSelfRef.m0_hwrite;
            vlSelfRef.s_htrans = vlSelfRef.m0_htrans;
            vlSelfRef.s_hsize = vlSelfRef.m0_hsize;
            vlSelfRef.s_hburst = vlSelfRef.m0_hburst;
            vlSelfRef.s_hprot = vlSelfRef.m0_hprot;
            vlSelfRef.s_hmastlock = vlSelfRef.m0_hmastlock;
            vlSelfRef.s_hmaster = vlSelfRef.m0_hmaster;
            vlSelfRef.s_hwdata = vlSelfRef.m0_hwdata;
        }
    }
}

bool Vahb_arbiter___024root___eval_phase__ico(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_phase__ico\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    Vahb_arbiter___024root___eval_triggers__ico(vlSelf);
    __VicoExecute = Vahb_arbiter___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        Vahb_arbiter___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vahb_arbiter___024root___eval_triggers__act(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_triggers__act\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((((~ (IData)(vlSelfRef.rst_n)) 
                                                       & (IData)(vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0)) 
                                                      << 1U) 
                                                     | ((IData)(vlSelfRef.clk) 
                                                        & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__clk__0))))));
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vahb_arbiter___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool Vahb_arbiter___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vahb_arbiter___024root___nba_sequent__TOP__0(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___nba_sequent__TOP__0\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (vlSelfRef.rst_n) {
        if (vlSelfRef.ahb_arbiter__DOT__busy) {
            if (vlSelfRef.s_hready) {
                vlSelfRef.ahb_arbiter__DOT__busy = 
                    (1U & ((IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)
                            ? ((IData)(vlSelfRef.m1_htrans) 
                               >> 1U) : ((IData)(vlSelfRef.m0_htrans) 
                                         >> 1U)));
            }
        } else {
            vlSelfRef.ahb_arbiter__DOT__busy = (1U 
                                                & (((IData)(vlSelfRef.m0_htrans) 
                                                    | (IData)(vlSelfRef.m1_htrans)) 
                                                   >> 1U));
        }
    } else {
        vlSelfRef.ahb_arbiter__DOT__busy = 0U;
    }
    vlSelfRef.ahb_arbiter__DOT__grant = ((IData)(vlSelfRef.rst_n) 
                                         && (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant));
    vlSelfRef.ahb_arbiter__DOT__arb_grant = (1U & ((IData)(vlSelfRef.ahb_arbiter__DOT__busy)
                                                    ? (IData)(vlSelfRef.ahb_arbiter__DOT__grant)
                                                    : 
                                                   ((~ 
                                                     ((IData)(vlSelfRef.m0_htrans) 
                                                      >> 1U)) 
                                                    & ((IData)(vlSelfRef.m1_htrans) 
                                                       >> 1U))));
    vlSelfRef.m0_hready = ((~ (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)) 
                           & (IData)(vlSelfRef.s_hready));
    if (vlSelfRef.ahb_arbiter__DOT__arb_grant) {
        vlSelfRef.m1_hready = vlSelfRef.s_hready;
        vlSelfRef.s_haddr = vlSelfRef.m1_haddr;
        vlSelfRef.s_hwrite = vlSelfRef.m1_hwrite;
        vlSelfRef.s_htrans = vlSelfRef.m1_htrans;
        vlSelfRef.s_hsize = vlSelfRef.m1_hsize;
        vlSelfRef.s_hburst = vlSelfRef.m1_hburst;
        vlSelfRef.s_hprot = vlSelfRef.m1_hprot;
        vlSelfRef.s_hmastlock = vlSelfRef.m1_hmastlock;
        vlSelfRef.s_hmaster = vlSelfRef.m1_hmaster;
        vlSelfRef.s_hwdata = vlSelfRef.m1_hwdata;
    } else {
        vlSelfRef.m1_hready = 0U;
        vlSelfRef.s_haddr = vlSelfRef.m0_haddr;
        vlSelfRef.s_hwrite = vlSelfRef.m0_hwrite;
        vlSelfRef.s_htrans = vlSelfRef.m0_htrans;
        vlSelfRef.s_hsize = vlSelfRef.m0_hsize;
        vlSelfRef.s_hburst = vlSelfRef.m0_hburst;
        vlSelfRef.s_hprot = vlSelfRef.m0_hprot;
        vlSelfRef.s_hmastlock = vlSelfRef.m0_hmastlock;
        vlSelfRef.s_hmaster = vlSelfRef.m0_hmaster;
        vlSelfRef.s_hwdata = vlSelfRef.m0_hwdata;
    }
}

void Vahb_arbiter___024root___eval_nba(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_nba\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        if (vlSelfRef.rst_n) {
            if (vlSelfRef.ahb_arbiter__DOT__busy) {
                if (vlSelfRef.s_hready) {
                    vlSelfRef.ahb_arbiter__DOT__busy 
                        = (1U & ((IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)
                                  ? ((IData)(vlSelfRef.m1_htrans) 
                                     >> 1U) : ((IData)(vlSelfRef.m0_htrans) 
                                               >> 1U)));
                }
            } else {
                vlSelfRef.ahb_arbiter__DOT__busy = 
                    (1U & (((IData)(vlSelfRef.m0_htrans) 
                            | (IData)(vlSelfRef.m1_htrans)) 
                           >> 1U));
            }
        } else {
            vlSelfRef.ahb_arbiter__DOT__busy = 0U;
        }
        vlSelfRef.ahb_arbiter__DOT__grant = ((IData)(vlSelfRef.rst_n) 
                                             && (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant));
        vlSelfRef.ahb_arbiter__DOT__arb_grant = (1U 
                                                 & ((IData)(vlSelfRef.ahb_arbiter__DOT__busy)
                                                     ? (IData)(vlSelfRef.ahb_arbiter__DOT__grant)
                                                     : 
                                                    ((~ 
                                                      ((IData)(vlSelfRef.m0_htrans) 
                                                       >> 1U)) 
                                                     & ((IData)(vlSelfRef.m1_htrans) 
                                                        >> 1U))));
        vlSelfRef.m0_hready = ((~ (IData)(vlSelfRef.ahb_arbiter__DOT__arb_grant)) 
                               & (IData)(vlSelfRef.s_hready));
        if (vlSelfRef.ahb_arbiter__DOT__arb_grant) {
            vlSelfRef.m1_hready = vlSelfRef.s_hready;
            vlSelfRef.s_haddr = vlSelfRef.m1_haddr;
            vlSelfRef.s_hwrite = vlSelfRef.m1_hwrite;
            vlSelfRef.s_htrans = vlSelfRef.m1_htrans;
            vlSelfRef.s_hsize = vlSelfRef.m1_hsize;
            vlSelfRef.s_hburst = vlSelfRef.m1_hburst;
            vlSelfRef.s_hprot = vlSelfRef.m1_hprot;
            vlSelfRef.s_hmastlock = vlSelfRef.m1_hmastlock;
            vlSelfRef.s_hmaster = vlSelfRef.m1_hmaster;
            vlSelfRef.s_hwdata = vlSelfRef.m1_hwdata;
        } else {
            vlSelfRef.m1_hready = 0U;
            vlSelfRef.s_haddr = vlSelfRef.m0_haddr;
            vlSelfRef.s_hwrite = vlSelfRef.m0_hwrite;
            vlSelfRef.s_htrans = vlSelfRef.m0_htrans;
            vlSelfRef.s_hsize = vlSelfRef.m0_hsize;
            vlSelfRef.s_hburst = vlSelfRef.m0_hburst;
            vlSelfRef.s_hprot = vlSelfRef.m0_hprot;
            vlSelfRef.s_hmastlock = vlSelfRef.m0_hmastlock;
            vlSelfRef.s_hmaster = vlSelfRef.m0_hmaster;
            vlSelfRef.s_hwdata = vlSelfRef.m0_hwdata;
        }
    }
}

void Vahb_arbiter___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vahb_arbiter___024root___eval_phase__act(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_phase__act\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vahb_arbiter___024root___eval_triggers__act(vlSelf);
    Vahb_arbiter___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vahb_arbiter___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vahb_arbiter___024root___eval_phase__nba(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_phase__nba\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vahb_arbiter___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vahb_arbiter___024root___eval_nba(vlSelf);
        Vahb_arbiter___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vahb_arbiter___024root___eval(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VicoIterCount;
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VicoIterCount = 0U;
    vlSelfRef.__VicoFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VicoIterCount)))) {
#ifdef VL_DEBUG
            Vahb_arbiter___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_arbiter.sv", 14, "", "Input combinational region did not converge after 100 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
    } while (Vahb_arbiter___024root___eval_phase__ico(vlSelf));
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vahb_arbiter___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_arbiter.sv", 14, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vahb_arbiter___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("rtl/soc/fabric/ahb_arbiter.sv", 14, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (Vahb_arbiter___024root___eval_phase__act(vlSelf));
    } while (Vahb_arbiter___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void Vahb_arbiter___024root___eval_debug_assertions(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_debug_assertions\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.rst_n & 0xfeU)))) {
        Verilated::overWidthError("rst_n");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_hwrite & 0xfeU)))) {
        Verilated::overWidthError("m0_hwrite");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_htrans & 0xfcU)))) {
        Verilated::overWidthError("m0_htrans");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_hsize & 0xf8U)))) {
        Verilated::overWidthError("m0_hsize");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_hburst & 0xf8U)))) {
        Verilated::overWidthError("m0_hburst");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_hprot & 0xf0U)))) {
        Verilated::overWidthError("m0_hprot");
    }
    if (VL_UNLIKELY(((vlSelfRef.m0_hmastlock & 0xfeU)))) {
        Verilated::overWidthError("m0_hmastlock");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_hwrite & 0xfeU)))) {
        Verilated::overWidthError("m1_hwrite");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_htrans & 0xfcU)))) {
        Verilated::overWidthError("m1_htrans");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_hsize & 0xf8U)))) {
        Verilated::overWidthError("m1_hsize");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_hburst & 0xf8U)))) {
        Verilated::overWidthError("m1_hburst");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_hprot & 0xf0U)))) {
        Verilated::overWidthError("m1_hprot");
    }
    if (VL_UNLIKELY(((vlSelfRef.m1_hmastlock & 0xfeU)))) {
        Verilated::overWidthError("m1_hmastlock");
    }
    if (VL_UNLIKELY(((vlSelfRef.s_hready & 0xfeU)))) {
        Verilated::overWidthError("s_hready");
    }
    if (VL_UNLIKELY(((vlSelfRef.s_hresp & 0xfeU)))) {
        Verilated::overWidthError("s_hresp");
    }
}
#endif  // VL_DEBUG
