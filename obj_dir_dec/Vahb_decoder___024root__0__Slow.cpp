// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_decoder.h for the primary calling header

#include "Vahb_decoder__pch.h"

VL_ATTR_COLD void Vahb_decoder___024root___eval_static(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_static\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
}

VL_ATTR_COLD void Vahb_decoder___024root___eval_initial(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_initial\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vahb_decoder___024root___eval_final(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_final\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vahb_decoder___024root___eval_phase__stl(Vahb_decoder___024root* vlSelf);

VL_ATTR_COLD void Vahb_decoder___024root___eval_settle(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_settle\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vahb_decoder___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_decoder.sv", 17, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (Vahb_decoder___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void Vahb_decoder___024root___eval_triggers__stl(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_triggers__stl\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vahb_decoder___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool Vahb_decoder___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_decoder___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vahb_decoder___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD void Vahb_decoder___024root___eval_stl(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_stl\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
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

VL_ATTR_COLD bool Vahb_decoder___024root___eval_phase__stl(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___eval_phase__stl\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vahb_decoder___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = Vahb_decoder___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vahb_decoder___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vahb_decoder___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_decoder___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

bool Vahb_decoder___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_decoder___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_decoder___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @(negedge rst_n)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vahb_decoder___024root___ctor_var_reset(Vahb_decoder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_decoder___024root___ctor_var_reset\n"); );
    Vahb_decoder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1638864771569018232ull);
    vlSelf->m_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7038444678382484845ull);
    vlSelf->m_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 973668439787245400ull);
    vlSelf->m_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 7775561830573256207ull);
    vlSelf->m_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 14389209179794782411ull);
    vlSelf->m_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4869276333718172236ull);
    vlSelf->m_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 617050538720585816ull);
    vlSelf->m_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3357961399045316334ull);
    vlSelf->m_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16955515016908863842ull);
    vlSelf->s0_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4939471419815105742ull);
    vlSelf->s0_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2451238061320176610ull);
    vlSelf->s0_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 13249282983281171394ull);
    vlSelf->s0_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 1706796240414399646ull);
    vlSelf->s0_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14627344220337862791ull);
    vlSelf->s0_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 4364129048790116607ull);
    vlSelf->s0_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1709392796647059378ull);
    vlSelf->s0_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 11815600026149519652ull);
    vlSelf->s1_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 6790042190671267227ull);
    vlSelf->s1_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 11197652917628735725ull);
    vlSelf->s1_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 16413889120368547269ull);
    vlSelf->s1_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 9018169249281285697ull);
    vlSelf->s1_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 9435922971787639232ull);
    vlSelf->s1_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 3524943008229766480ull);
    vlSelf->s1_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1679576124299953869ull);
    vlSelf->s1_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13879695811564104217ull);
    vlSelf->ahb_decoder__DOT__sel_r = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4864742326236077190ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VicoTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = 0;
    vlSelf->__Vtrigprevexpr___TOP__rst_n__0 = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
