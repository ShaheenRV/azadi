// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VAzadi_top_verilator.h for the primary calling header

#ifndef _VAZADI_TOP_VERILATOR_RV_TIMER_REG_PKG_H_
#define _VAZADI_TOP_VERILATOR_RV_TIMER_REG_PKG_H_  // guard

#include "verilated_heavy.h"
#include "verilated_threads.h"
#include "VAzadi_top_verilator__Dpi.h"

//==========

class VAzadi_top_verilator__Syms;
<<<<<<< HEAD
class VAzadi_top_verilator_VerilatedFst;
=======
class VAzadi_top_verilator_VerilatedVcd;
>>>>>>> 8883d9b324c489ad01ca11f681acb89fb7eab79d


//----------

VL_MODULE(VAzadi_top_verilator_rv_timer_reg_pkg) {
  public:
    
    // INTERNAL VARIABLES
  private:
    VAzadi_top_verilator__Syms* __VlSymsp;  // Symbol table
  public:
    
    // PARAMETERS
    // Begin mtask footprint all: 
    CData/*3:0*/ __PVT__RV_TIMER_PERMIT[9];
    
    // CONSTRUCTORS
  private:
    VL_UNCOPYABLE(VAzadi_top_verilator_rv_timer_reg_pkg);  ///< Copying not allowed
  public:
    VAzadi_top_verilator_rv_timer_reg_pkg(const char* name = "TOP");
    ~VAzadi_top_verilator_rv_timer_reg_pkg();
    
    // INTERNAL METHODS
    void __Vconfigure(VAzadi_top_verilator__Syms* symsp, bool first);
  private:
    void _ctor_var_reset() VL_ATTR_COLD;
  public:
    static void _initial__TOP__rv_timer_reg_pkg__1(VAzadi_top_verilator__Syms* __restrict vlSymsp) VL_ATTR_COLD;
  private:
<<<<<<< HEAD
    static void traceInit(void* userp, VerilatedFst* tracep, uint32_t code) VL_ATTR_COLD;
=======
    static void traceInit(void* userp, VerilatedVcd* tracep, uint32_t code) VL_ATTR_COLD;
>>>>>>> 8883d9b324c489ad01ca11f681acb89fb7eab79d
} VL_ATTR_ALIGNED(VL_CACHE_LINE_BYTES);

//----------


#endif  // guard
