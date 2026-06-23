// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vahb_arbiter__pch.h"

//============================================================
// Constructors

Vahb_arbiter::Vahb_arbiter(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vahb_arbiter__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst_n{vlSymsp->TOP.rst_n}
    , m0_hwrite{vlSymsp->TOP.m0_hwrite}
    , m0_htrans{vlSymsp->TOP.m0_htrans}
    , m0_hsize{vlSymsp->TOP.m0_hsize}
    , m0_hburst{vlSymsp->TOP.m0_hburst}
    , m0_hprot{vlSymsp->TOP.m0_hprot}
    , m0_hmastlock{vlSymsp->TOP.m0_hmastlock}
    , m0_hmaster{vlSymsp->TOP.m0_hmaster}
    , m0_hready{vlSymsp->TOP.m0_hready}
    , m0_hresp{vlSymsp->TOP.m0_hresp}
    , m1_hwrite{vlSymsp->TOP.m1_hwrite}
    , m1_htrans{vlSymsp->TOP.m1_htrans}
    , m1_hsize{vlSymsp->TOP.m1_hsize}
    , m1_hburst{vlSymsp->TOP.m1_hburst}
    , m1_hprot{vlSymsp->TOP.m1_hprot}
    , m1_hmastlock{vlSymsp->TOP.m1_hmastlock}
    , m1_hmaster{vlSymsp->TOP.m1_hmaster}
    , m1_hready{vlSymsp->TOP.m1_hready}
    , m1_hresp{vlSymsp->TOP.m1_hresp}
    , s_hwrite{vlSymsp->TOP.s_hwrite}
    , s_htrans{vlSymsp->TOP.s_htrans}
    , s_hsize{vlSymsp->TOP.s_hsize}
    , s_hburst{vlSymsp->TOP.s_hburst}
    , s_hprot{vlSymsp->TOP.s_hprot}
    , s_hmastlock{vlSymsp->TOP.s_hmastlock}
    , s_hmaster{vlSymsp->TOP.s_hmaster}
    , s_hready{vlSymsp->TOP.s_hready}
    , s_hresp{vlSymsp->TOP.s_hresp}
    , m0_haddr{vlSymsp->TOP.m0_haddr}
    , m0_hwdata{vlSymsp->TOP.m0_hwdata}
    , m0_hrdata{vlSymsp->TOP.m0_hrdata}
    , m1_haddr{vlSymsp->TOP.m1_haddr}
    , m1_hwdata{vlSymsp->TOP.m1_hwdata}
    , m1_hrdata{vlSymsp->TOP.m1_hrdata}
    , s_haddr{vlSymsp->TOP.s_haddr}
    , s_hwdata{vlSymsp->TOP.s_hwdata}
    , s_hrdata{vlSymsp->TOP.s_hrdata}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vahb_arbiter::Vahb_arbiter(const char* _vcname__)
    : Vahb_arbiter(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vahb_arbiter::~Vahb_arbiter() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vahb_arbiter___024root___eval_debug_assertions(Vahb_arbiter___024root* vlSelf);
#endif  // VL_DEBUG
void Vahb_arbiter___024root___eval_static(Vahb_arbiter___024root* vlSelf);
void Vahb_arbiter___024root___eval_initial(Vahb_arbiter___024root* vlSelf);
void Vahb_arbiter___024root___eval_settle(Vahb_arbiter___024root* vlSelf);
void Vahb_arbiter___024root___eval(Vahb_arbiter___024root* vlSelf);

void Vahb_arbiter::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vahb_arbiter::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vahb_arbiter___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vahb_arbiter___024root___eval_static(&(vlSymsp->TOP));
        Vahb_arbiter___024root___eval_initial(&(vlSymsp->TOP));
        Vahb_arbiter___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vahb_arbiter___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vahb_arbiter::eventsPending() { return false; }

uint64_t Vahb_arbiter::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vahb_arbiter::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vahb_arbiter___024root___eval_final(Vahb_arbiter___024root* vlSelf);

VL_ATTR_COLD void Vahb_arbiter::final() {
    Vahb_arbiter___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vahb_arbiter::hierName() const { return vlSymsp->name(); }
const char* Vahb_arbiter::modelName() const { return "Vahb_arbiter"; }
unsigned Vahb_arbiter::threads() const { return 1; }
void Vahb_arbiter::prepareClone() const { contextp()->prepareClone(); }
void Vahb_arbiter::atClone() const {
    contextp()->threadPoolpOnClone();
}
