// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Primary model header
//
// This header should be included by all source files instantiating the design.
// The class here is then constructed to instantiate the design.
// See the Verilator manual for examples.

#ifndef VERILATED_VAHB_ARBITER_H_
#define VERILATED_VAHB_ARBITER_H_  // guard

#include "verilated.h"

class Vahb_arbiter__Syms;
class Vahb_arbiter___024root;

// This class is the main interface to the Verilated model
class alignas(VL_CACHE_LINE_BYTES) Vahb_arbiter VL_NOT_FINAL : public VerilatedModel {
  private:
    // Symbol table holding complete model state (owned by this class)
    Vahb_arbiter__Syms* const vlSymsp;

  public:

    // CONSTEXPR CAPABILITIES
    // Verilated with --trace?
    static constexpr bool traceCapable = false;

    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(&clk,0,0);
    VL_IN8(&rst_n,0,0);
    VL_IN8(&m0_hwrite,0,0);
    VL_IN8(&m0_htrans,1,0);
    VL_IN8(&m0_hsize,2,0);
    VL_IN8(&m0_hburst,2,0);
    VL_IN8(&m0_hprot,3,0);
    VL_IN8(&m0_hmastlock,0,0);
    VL_IN8(&m0_hmaster,7,0);
    VL_OUT8(&m0_hready,0,0);
    VL_OUT8(&m0_hresp,0,0);
    VL_IN8(&m1_hwrite,0,0);
    VL_IN8(&m1_htrans,1,0);
    VL_IN8(&m1_hsize,2,0);
    VL_IN8(&m1_hburst,2,0);
    VL_IN8(&m1_hprot,3,0);
    VL_IN8(&m1_hmastlock,0,0);
    VL_IN8(&m1_hmaster,7,0);
    VL_OUT8(&m1_hready,0,0);
    VL_OUT8(&m1_hresp,0,0);
    VL_OUT8(&s_hwrite,0,0);
    VL_OUT8(&s_htrans,1,0);
    VL_OUT8(&s_hsize,2,0);
    VL_OUT8(&s_hburst,2,0);
    VL_OUT8(&s_hprot,3,0);
    VL_OUT8(&s_hmastlock,0,0);
    VL_OUT8(&s_hmaster,7,0);
    VL_IN8(&s_hready,0,0);
    VL_IN8(&s_hresp,0,0);
    VL_IN(&m0_haddr,31,0);
    VL_IN(&m0_hwdata,31,0);
    VL_OUT(&m0_hrdata,31,0);
    VL_IN(&m1_haddr,31,0);
    VL_IN(&m1_hwdata,31,0);
    VL_OUT(&m1_hrdata,31,0);
    VL_OUT(&s_haddr,31,0);
    VL_OUT(&s_hwdata,31,0);
    VL_IN(&s_hrdata,31,0);

    // CELLS
    // Public to allow access to /* verilator public */ items.
    // Otherwise the application code can consider these internals.

    // Root instance pointer to allow access to model internals,
    // including inlined /* verilator public_flat_* */ items.
    Vahb_arbiter___024root* const rootp;

    // CONSTRUCTORS
    /// Construct the model; called by application code
    /// If contextp is null, then the model will use the default global context
    /// If name is "", then makes a wrapper with a
    /// single model invisible with respect to DPI scope names.
    explicit Vahb_arbiter(VerilatedContext* contextp, const char* name = "TOP");
    explicit Vahb_arbiter(const char* name = "TOP");
    /// Destroy the model; called (often implicitly) by application code
    virtual ~Vahb_arbiter();
  private:
    VL_UNCOPYABLE(Vahb_arbiter);  ///< Copying not allowed

  public:
    // API METHODS
    /// Evaluate the model.  Application must call when inputs change.
    void eval() { eval_step(); }
    /// Evaluate when calling multiple units/models per time step.
    void eval_step();
    /// Evaluate at end of a timestep for tracing, when using eval_step().
    /// Application must call after all eval() and before time changes.
    void eval_end_step() {}
    /// Simulation complete, run final blocks.  Application must call on completion.
    void final();
    /// Are there scheduled events to handle?
    bool eventsPending();
    /// Returns time at next time slot. Aborts if !eventsPending()
    uint64_t nextTimeSlot();
    /// Trace signals in the model; called by application code
    void trace(VerilatedTraceBaseC* tfp, int levels, int options = 0) { contextp()->trace(tfp, levels, options); }
    /// Retrieve name of this model instance (as passed to constructor).
    const char* name() const;

    // Abstract methods from VerilatedModel
    const char* hierName() const override final;
    const char* modelName() const override final;
    unsigned threads() const override final;
    /// Prepare for cloning the model at the process level (e.g. fork in Linux)
    /// Release necessary resources. Called before cloning.
    void prepareClone() const;
    /// Re-init after cloning the model at the process level (e.g. fork in Linux)
    /// Re-allocate necessary resources. Called after cloning.
    void atClone() const;
  private:
    // Internal functions - trace registration
    void traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options);
};

#endif  // guard
