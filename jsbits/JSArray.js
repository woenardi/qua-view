#include <ghcjs/rts.h>
"use strict";

function h$runSyncActionUnsafe(t, a, cont) {
  h$runInitStatic();
  var c = h$return;
  t.stack[2] = h$ghcjszmprimZCGHCJSziPrimziInternalzisetCurrentThreadResultException;
  t.stack[4] = h$ap_1_0;
  t.stack[5] = a;
  t.stack[6] = h$return;
  t.sp = 6;
  t.status = (0);
  t.isSynchronous = true;
  t.continueAsync = cont;
  var ct = h$currentThread;
  var csp = h$sp;
  var cr1 = h$r1; // do we need to save more than this?
  h$currentThread = t;
  h$stack = t.stack;
  h$sp = t.sp;
  while(c !== h$reschedule){c = c();}
  if(ct !== null) {
    h$currentThread = ct;
    h$stack = ct.stack;
    h$sp = csp;
    h$r1 = cr1;
  } else {
    h$currentThread = null;
    h$stack = null;
  }
  if(t.status !== (16) && !cont) {
    h$removeThreadBlock(t);
    h$finishThread(t);
  }
}

function h$runSyncReturnUnsafe(a, cont) {
  var t = new h$Thread();
  var aa = (h$c2(h$ap1_e,(h$ghcjszmprimZCGHCJSziPrimziInternalzisetCurrentThreadResultValue),(a)));
  h$runSyncActionUnsafe(t, aa, cont);
  if(t.status === (16)) {
    if(t.resultIsException) {
      throw t.result;
    } else {
      return t.result;
    }
  } else if(t.status === (1)) {
    throw new h$WouldBlock();
  } else {
    throw new Error("h$runSyncReturn: Unexpected thread status: " + t.status)
  }
}

/*
   convert an array to a Haskell list, wrapping each element in a
   JSVal constructor
 */
function h$JSArrayToList(a) {
    var r = HS_NIL;
    for(var i=a.length-1;i>=0;i--) r = MK_CONS(MK_JSVAL(a[i]), r);
    return r;
}

/*
   convert a list of JSVal to an array. the list must have been fully forced,
   not just the spine.
 */
function h$ListToJSArray(xs) {
    var a = [];
    while(IS_CONS(xs)) {
	a.push(JSVAL_VAL(CONS_HEAD(xs)));
	xs = CONS_TAIL(xs);
    }
    return a;
}

// Safe function undefined treatment

function h$isDefined(a) {
    return a !== undefined && a !== null;
}
function h$retIfDef(f) {
    return function(a,i){return (a !== undefined && a !== null) ? f(a,i) : undefined;};
}
function h$doIfDef(f) {
    return function(a,i){if(a !== undefined && a !== null){f(a,i);}};
}
function h$retIfDef2(f) {
    return function(a,b,i){return (a !== undefined && a !== null && b !== undefined && b !== null) ? f(a,b,i) : undefined;};
}
function h$doIfDef2(f) {
    return function(a,b,i){if(a !== undefined && a !== null && b !== undefined && b !== null){f(a,b,i);}};
}
function h$retIfDef2o(f) {
    return function(a,b,i){return (b !== undefined && b !== null) ? f(a,b,i) : undefined;};
}
function h$retIfDef2oa(f) {
    return function(a,b,i){return (b !== undefined && b !== null) ? f(a,b,i) : a;};
}
function h$doIfDef2o(f) {
    return function(a,b,i){if(b !== undefined && b !== null){f(a,b,i);}};
}
