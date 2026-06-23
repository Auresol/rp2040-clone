// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vahb_arbiter.h for the primary calling header

#include "Vahb_arbiter__pch.h"

VL_ATTR_COLD void Vahb_arbiter___024root___eval_static(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_static\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__clk__0 = vlSelfRef.clk;
    vlSelfRef.__Vtrigprevexpr___TOP__rst_n__0 = vlSelfRef.rst_n;
}

VL_ATTR_COLD void Vahb_arbiter___024root___eval_initial(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_initial\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void Vahb_arbiter___024root___eval_final(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_final\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vahb_arbiter___024root___eval_phase__stl(Vahb_arbiter___024root* vlSelf);

VL_ATTR_COLD void Vahb_arbiter___024root___eval_settle(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_settle\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vahb_arbiter___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("rtl/soc/fabric/ahb_arbiter.sv", 14, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (Vahb_arbiter___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void Vahb_arbiter___024root___eval_triggers__stl(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_triggers__stl\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vahb_arbiter___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool Vahb_arbiter___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_arbiter___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vahb_arbiter___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD void Vahb_arbiter___024root___eval_stl(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_stl\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
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

VL_ATTR_COLD bool Vahb_arbiter___024root___eval_phase__stl(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___eval_phase__stl\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vahb_arbiter___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = Vahb_arbiter___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vahb_arbiter___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vahb_arbiter___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_arbiter___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

bool Vahb_arbiter___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vahb_arbiter___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vahb_arbiter___024root___trigger_anySet__act(triggers))))) {
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

VL_ATTR_COLD void Vahb_arbiter___024root___ctor_var_reset(Vahb_arbiter___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vahb_arbiter___024root___ctor_var_reset\n"); );
    Vahb_arbiter__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16707436170211756652ull);
    vlSelf->rst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1638864771569018232ull);
    vlSelf->m0_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 10848390700815002019ull);
    vlSelf->m0_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15832059928372493172ull);
    vlSelf->m0_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 6075812936174746515ull);
    vlSelf->m0_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 3525990307495995860ull);
    vlSelf->m0_hburst = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 10058343076021700685ull);
    vlSelf->m0_hprot = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 16211562608943862326ull);
    vlSelf->m0_hmastlock = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7898865631275907207ull);
    vlSelf->m0_hmaster = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 17855888509527997802ull);
    vlSelf->m0_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11831617946567083345ull);
    vlSelf->m0_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 5892321596651755684ull);
    vlSelf->m0_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4445486279705858290ull);
    vlSelf->m0_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3584812935445416054ull);
    vlSelf->m1_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 17419025736696899580ull);
    vlSelf->m1_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6676438991902551033ull);
    vlSelf->m1_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 11589178056103016139ull);
    vlSelf->m1_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 13868016454403458116ull);
    vlSelf->m1_hburst = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 12563439462886982052ull);
    vlSelf->m1_hprot = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 1284861213669891111ull);
    vlSelf->m1_hmastlock = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9437759378442944811ull);
    vlSelf->m1_hmaster = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 13201827921791262234ull);
    vlSelf->m1_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7416089068905473245ull);
    vlSelf->m1_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14381489754685911644ull);
    vlSelf->m1_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17484205327001970968ull);
    vlSelf->m1_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15911511946617216710ull);
    vlSelf->s_haddr = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12224129909778235308ull);
    vlSelf->s_hwrite = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3136188794147958163ull);
    vlSelf->s_htrans = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 6175535038274773579ull);
    vlSelf->s_hsize = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 14572370915144626647ull);
    vlSelf->s_hburst = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 12008649082516875543ull);
    vlSelf->s_hprot = VL_SCOPED_RAND_RESET_I(4, __VscopeHash, 1593725568389542084ull);
    vlSelf->s_hmastlock = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4882316419964307767ull);
    vlSelf->s_hmaster = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 13512713978736579772ull);
    vlSelf->s_hwdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 18330548363251301152ull);
    vlSelf->s_hrdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 13815447487665006323ull);
    vlSelf->s_hready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16516259308423208648ull);
    vlSelf->s_hresp = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15992332816936993453ull);
    vlSelf->ahb_arbiter__DOT__grant = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6500339886013830145ull);
    vlSelf->ahb_arbiter__DOT__busy = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3937977325248121056ull);
    vlSelf->ahb_arbiter__DOT__arb_grant = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4313381184407806505ull);
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
