// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vadder.h for the primary calling header

#ifndef VERILATED_VADDER___024UNIT_H_
#define VERILATED_VADDER___024UNIT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vadder__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vadder___024unit final {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ __VmonitorOff;
    QData/*63:0*/ __VmonitorNum;

    // INTERNAL VARIABLES
    Vadder__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vadder___024unit();
    ~Vadder___024unit();
    void ctor(Vadder__Syms* symsp, const char* namep);
    void dtor();
    VL_UNCOPYABLE(Vadder___024unit);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
