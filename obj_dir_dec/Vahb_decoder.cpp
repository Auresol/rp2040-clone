// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vahb_decoder__pch.h"

//============================================================
// Constructors

Vahb_decoder::Vahb_decoder(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vahb_decoder__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , rst_n{vlSymsp->TOP.rst_n}
    , m_hwrite{vlSymsp->TOP.m_hwrite}
    , m_htrans{vlSymsp->TOP.m_htrans}
    , m_hsize{vlSymsp->TOP.m_hsize}
    , m_hready{vlSymsp->TOP.m_hready}
    , m_hresp{vlSymsp->TOP.m_hresp}
    , s0_hwrite{vlSymsp->TOP.s0_hwrite}
    , s0_htrans{vlSymsp->TOP.s0_htrans}
    , s0_hsize{vlSymsp->TOP.s0_hsize}
    , s0_hready{vlSymsp->TOP.s0_hready}
    , s0_hresp{vlSymsp->TOP.s0_hresp}
    , s1_hwrite{vlSymsp->TOP.s1_hwrite}
    , s1_htrans{vlSymsp->TOP.s1_htrans}
    , s1_hsize{vlSymsp->TOP.s1_hsize}
    , s1_hready{vlSymsp->TOP.s1_hready}
    , s1_hresp{vlSymsp->TOP.s1_hresp}
    , m_haddr{vlSymsp->TOP.m_haddr}
    , m_hwdata{vlSymsp->TOP.m_hwdata}
    , m_hrdata{vlSymsp->TOP.m_hrdata}
    , s0_haddr{vlSymsp->TOP.s0_haddr}
    , s0_hwdata{vlSymsp->TOP.s0_hwdata}
    , s0_hrdata{vlSymsp->TOP.s0_hrdata}
    , s1_haddr{vlSymsp->TOP.s1_haddr}
    , s1_hwdata{vlSymsp->TOP.s1_hwdata}
    , s1_hrdata{vlSymsp->TOP.s1_hrdata}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vahb_decoder::Vahb_decoder(const char* _vcname__)
    : Vahb_decoder(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vahb_decoder::~Vahb_decoder() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vahb_decoder___024root___eval_debug_assertions(Vahb_decoder___024root* vlSelf);
#endif  // VL_DEBUG
void Vahb_decoder___024root___eval_static(Vahb_decoder___024root* vlSelf);
void Vahb_decoder___024root___eval_initial(Vahb_decoder___024root* vlSelf);
void Vahb_decoder___024root___eval_settle(Vahb_decoder___024root* vlSelf);
void Vahb_decoder___024root___eval(Vahb_decoder___024root* vlSelf);

void Vahb_decoder::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vahb_decoder::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vahb_decoder___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vahb_decoder___024root___eval_static(&(vlSymsp->TOP));
        Vahb_decoder___024root___eval_initial(&(vlSymsp->TOP));
        Vahb_decoder___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vahb_decoder___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vahb_decoder::eventsPending() { return false; }

uint64_t Vahb_decoder::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vahb_decoder::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vahb_decoder___024root___eval_final(Vahb_decoder___024root* vlSelf);

VL_ATTR_COLD void Vahb_decoder::final() {
    Vahb_decoder___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vahb_decoder::hierName() const { return vlSymsp->name(); }
const char* Vahb_decoder::modelName() const { return "Vahb_decoder"; }
unsigned Vahb_decoder::threads() const { return 1; }
void Vahb_decoder::prepareClone() const { contextp()->prepareClone(); }
void Vahb_decoder::atClone() const {
    contextp()->threadPoolpOnClone();
}
