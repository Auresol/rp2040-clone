// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_decoder.h for the primary calling header

#include "Vahb_decoder__pch.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vahb_decoder___024root___eval_triggers__ico(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_triggers__ico\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VicoTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VicoFirstIteration)));
    vlSelfRef.__VicoFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vahb_decoder___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
}

bool Vahb_decoder___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___trigger_anySet__ico\n"); );
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

void Vahb_decoder___024root___ico_sequent__TOP__0(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___ico_sequent__TOP__0\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.s0_haddr = vlSelfRef.m_haddr;
    vlSelfRef.s1_haddr = vlSelfRef.m_haddr;
    vlSelfRef.s0_hwrite = vlSelfRef.m_hwrite;
    vlSelfRef.s1_hwrite = vlSelfRef.m_hwrite;
    vlSelfRef.s0_hsize = vlSelfRef.m_hsize;
    vlSelfRef.s1_hsize = vlSelfRef.m_hsize;
    vlSelfRef.s0_hwdata = vlSelfRef.m_hwdata;
    vlSelfRef.s1_hwdata = vlSelfRef.m_hwdata;
    if ((0x4000U == (vlSelfRef.m_haddr >> 0x00000010U))) {
        vlSelfRef.s0_htrans = 0U;
        vlSelfRef.s1_htrans = vlSelfRef.m_htrans;
    } else {
        vlSelfRef.s0_htrans = vlSelfRef.m_htrans;
        vlSelfRef.s1_htrans = 0U;
    }
    if (vlSelfRef.ahb_decoder__DOT__sel_r) {
        vlSelfRef.m_hrdata = vlSelfRef.s1_hrdata;
        vlSelfRef.m_hready = vlSelfRef.s1_hready;
        vlSelfRef.m_hresp = vlSelfRef.s1_hresp;
    } else {
        vlSelfRef.m_hrdata = vlSelfRef.s0_hrdata;
        vlSelfRef.m_hready = vlSelfRef.s0_hready;
        vlSelfRef.m_hresp = vlSelfRef.s0_hresp;
    }
}

void Vahb_decoder___024root___eval_ico(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_ico\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VicoTriggered[0U])) {
        vlSelfRef.s0_haddr = vlSelfRef.m_haddr;
        vlSelfRef.s1_haddr = vlSelfRef.m_haddr;
        vlSelfRef.s0_hwrite = vlSelfRef.m_hwrite;
        vlSelfRef.s1_hwrite = vlSelfRef.m_hwrite;
        vlSelfRef.s0_hsize = vlSelfRef.m_hsize;
        vlSelfRef.s1_hsize = vlSelfRef.m_hsize;
        vlSelfRef.s0_hwdata = vlSelfRef.m_hwdata;
        vlSelfRef.s1_hwdata = vlSelfRef.m_hwdata;
        if ((0x4000U == (vlSelfRef.m_haddr >> 0x00000010U))) {
            vlSelfRef.s0_htrans = 0U;
            vlSelfRef.s1_htrans = vlSelfRef.m_htrans;
        } else {
            vlSelfRef.s0_htrans = vlSelfRef.m_htrans;
            vlSelfRef.s1_htrans = 0U;
        }
        if (vlSelfRef.ahb_decoder__DOT__sel_r) {
            vlSelfRef.m_hrdata = vlSelfRef.s1_hrdata;
            vlSelfRef.m_hready = vlSelfRef.s1_hready;
            vlSelfRef.m_hresp = vlSelfRef.s1_hresp;
        } else {
            vlSelfRef.m_hrdata = vlSelfRef.s0_hrdata;
            vlSelfRef.m_hready = vlSelfRef.s0_hready;
            vlSelfRef.m_hresp = vlSelfRef.s0_hresp;
        }
    }
}

bool Vahb_decoder___024root___eval_phase__ico(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_phase__ico\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    Vahb_decoder___024root___eval_triggers__ico(vlSelf);
    __VicoExecute = Vahb_decoder___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        Vahb_decoder___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vahb_decoder___024root___eval_triggers__act(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_triggers__act\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
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
        Vahb_decoder___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool Vahb_decoder___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___trigger_anySet__act\n"); );
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

void Vahb_decoder___024root___nba_sequent__TOP__0(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___nba_sequent__TOP__0\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.ahb_decoder__DOT__sel_r = ((IData)(vlSelfRef.rst_n) 
                                         & (0x4000U 
                                            == (vlSelfRef.m_haddr 
                                                >> 0x00000010U)));
    if (vlSelfRef.ahb_decoder__DOT__sel_r) {
        vlSelfRef.m_hrdata = vlSelfRef.s1_hrdata;
        vlSelfRef.m_hready = vlSelfRef.s1_hready;
        vlSelfRef.m_hresp = vlSelfRef.s1_hresp;
    } else {
        vlSelfRef.m_hrdata = vlSelfRef.s0_hrdata;
        vlSelfRef.m_hready = vlSelfRef.s0_hready;
        vlSelfRef.m_hresp = vlSelfRef.s0_hresp;
    }
}

void Vahb_decoder___024root___eval_nba(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_nba\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        vlSelfRef.ahb_decoder__DOT__sel_r = ((IData)(vlSelfRef.rst_n) 
                                             & (0x4000U 
                                                == 
                                                (vlSelfRef.m_haddr 
                                                 >> 0x00000010U)));
        if (vlSelfRef.ahb_decoder__DOT__sel_r) {
            vlSelfRef.m_hrdata = vlSelfRef.s1_hrdata;
            vlSelfRef.m_hready = vlSelfRef.s1_hready;
            vlSelfRef.m_hresp = vlSelfRef.s1_hresp;
        } else {
            vlSelfRef.m_hrdata = vlSelfRef.s0_hrdata;
            vlSelfRef.m_hready = vlSelfRef.s0_hready;
            vlSelfRef.m_hresp = vlSelfRef.s0_hresp;
        }
    }
}

void Vahb_decoder___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vahb_decoder___024root___eval_phase__act(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_phase__act\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vahb_decoder___024root___eval_triggers__act(vlSelf);
    Vahb_decoder___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    return (0U);
}

void Vahb_decoder___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vahb_decoder___024root___eval_phase__nba(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_phase__nba\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vahb_decoder___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vahb_decoder___024root___eval_nba(vlSelf);
        Vahb_decoder___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vahb_decoder___024root___eval(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
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
            Vahb_decoder___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_decoder.sv", 17, "", "Input combinational region did not converge after 100 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
    } while (Vahb_decoder___024root___eval_phase__ico(vlSelf));
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vahb_decoder___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_decoder.sv", 17, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vahb_decoder___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("rtl/soc/fabric/ahb_decoder.sv", 17, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (Vahb_decoder___024root___eval_phase__act(vlSelf));
    } while (Vahb_decoder___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void Vahb_decoder___024root___eval_debug_assertions(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_debug_assertions\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clk & 0xfeU)))) {
        Verilated::overWidthError("clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.rst_n & 0xfeU)))) {
        Verilated::overWidthError("rst_n");
    }
    if (VL_UNLIKELY(((vlSelfRef.m_hwrite & 0xfeU)))) {
        Verilated::overWidthError("m_hwrite");
    }
    if (VL_UNLIKELY(((vlSelfRef.m_htrans & 0xfcU)))) {
        Verilated::overWidthError("m_htrans");
    }
    if (VL_UNLIKELY(((vlSelfRef.m_hsize & 0xf8U)))) {
        Verilated::overWidthError("m_hsize");
    }
    if (VL_UNLIKELY(((vlSelfRef.s0_hready & 0xfeU)))) {
        Verilated::overWidthError("s0_hready");
    }
    if (VL_UNLIKELY(((vlSelfRef.s0_hresp & 0xfeU)))) {
        Verilated::overWidthError("s0_hresp");
    }
    if (VL_UNLIKELY(((vlSelfRef.s1_hready & 0xfeU)))) {
        Verilated::overWidthError("s1_hready");
    }
    if (VL_UNLIKELY(((vlSelfRef.s1_hresp & 0xfeU)))) {
        Verilated::overWidthError("s1_hresp");
    }
}
#endif  // VL_DEBUG
