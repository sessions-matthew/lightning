// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vadder__pch.h"

//============================================================
// Constructors

Vadder::Vadder(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vadder__Syms(contextp(), _vcname__, this)}
    , m_evalLoop{*this, /*convergeLimit:*/ 10000}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vadder::Vadder(const char* _vcname__)
    : Vadder(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vadder::~Vadder() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vadder___024root___eval_debug_assertions(Vadder___024root* vlSelf);
#endif  // VL_DEBUG
VL_ATTR_COLD void Vadder___024root___eval_static(Vadder___024root* vlSelf);
void Vadder___024root___eval_initial(Vadder___024root* vlSelf);
VL_ATTR_COLD bool Vadder___024root___eval_stl(Vadder___024root* vlSelf, CData/*0:0*/ firstIteration);
void Vadder___024root___eval_sample(Vadder___024root* vlSelf);
bool Vadder___024root___eval_ico(Vadder___024root* vlSelf, CData/*0:0*/ firstIteration);
bool Vadder___024root___eval_act(Vadder___024root* vlSelf);
bool Vadder___024root___eval_inact(Vadder___024root* vlSelf);
bool Vadder___024root___eval_nba(Vadder___024root* vlSelf);
bool Vadder___024root___eval_obs(Vadder___024root* vlSelf);
bool Vadder___024root___eval_react(Vadder___024root* vlSelf);
void Vadder___024root___eval_postponed(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_final(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__stl(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__ico(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__act(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__nba(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__obs(Vadder___024root* vlSelf);
VL_ATTR_COLD void Vadder___024root___eval_dump_triggers__react(Vadder___024root* vlSelf);

void Vadder::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vadder::eval_step\n"); );
    m_evalLoop.eval();
}

void Vadder::evalBegin() {
#ifdef VL_DEBUG
    // Debug assertions
    Vadder___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
}

void Vadder::evalEnd() {
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
    vlSymsp->TOP.__VdlySched.cleanupForevered();
}

void Vadder::evalStatic() {
    Vadder___024root___eval_static(&(vlSymsp->TOP));
}

void Vadder::evalInitial() {
    Vadder___024root___eval_initial(&(vlSymsp->TOP));
}

bool Vadder::evalStl(bool firstIteration) {
    return Vadder___024root___eval_stl(&(vlSymsp->TOP), firstIteration);
}

void Vadder::evalSample() {
    Vadder___024root___eval_sample(&(vlSymsp->TOP));
}

bool Vadder::evalIco(bool firstIteration) {
    return Vadder___024root___eval_ico(&(vlSymsp->TOP), firstIteration);
}

bool Vadder::evalAct() {
    return Vadder___024root___eval_act(&(vlSymsp->TOP));
}

bool Vadder::evalInact() {
    return Vadder___024root___eval_inact(&(vlSymsp->TOP));
}

bool Vadder::evalNba() {
    return Vadder___024root___eval_nba(&(vlSymsp->TOP));
}

bool Vadder::evalObs() {
    return Vadder___024root___eval_obs(&(vlSymsp->TOP));
}

bool Vadder::evalReact() {
    return Vadder___024root___eval_react(&(vlSymsp->TOP));
}

void Vadder::evalPostponed() {
    Vadder___024root___eval_postponed(&(vlSymsp->TOP));
}

void Vadder::evalFinal() {
    Vadder___024root___eval_final(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersStl() {
    Vadder___024root___eval_dump_triggers__stl(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersIco() {
    Vadder___024root___eval_dump_triggers__ico(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersAct() {
    Vadder___024root___eval_dump_triggers__act(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersNba() {
    Vadder___024root___eval_dump_triggers__nba(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersObs() {
    Vadder___024root___eval_dump_triggers__obs(&(vlSymsp->TOP));
}

VL_ATTR_COLD void Vadder::dumpTriggersReact() {
    Vadder___024root___eval_dump_triggers__react(&(vlSymsp->TOP));
}

//============================================================
// Events and timing
bool Vadder::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty() && !contextp()->gotFinish(); }

uint64_t Vadder::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* Vadder::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

VL_ATTR_COLD void Vadder::final() {
    contextp()->executingFinal(true);
    evalFinal();
    contextp()->executingFinal(false);
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vadder::hierName() const { return vlSymsp->name(); }
const char* Vadder::modelName() const { return "Vadder"; }
unsigned Vadder::threads() const { return 1; }
void Vadder::prepareClone() const { contextp()->prepareClone(); }
void Vadder::atClone() const {
    contextp()->threadPoolpOnClone();
}
