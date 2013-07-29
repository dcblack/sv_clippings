`ifndef MUTEX_CLASS_H
`define MUTEX_CLASS_H
////////////////////////////////////////////////////////////////////////////////
// VERSION
//   Mutex version 2

////////////////////////////////////////////////////////////////////////////////
// DESCRIPTION
// 
// The following class implements a safe mutex derived as a semaphore with
// keycount of 1. It returns errors when attempting to lock an already owned
// mutex or unlock and unowned mutex. As a feature, you may also specify a
// timeout, when attempting to lock. A default timeout is also available during
// construction.
//
// Feature: you can redefine how errors are reported by defining the macro
// `MUTEX_ERROR(message) prior to including this file.
//
// Define UNIT_TEST to run a self-test of this code. Or examine it for examples
// of usage.


////////////////////////////////////////////////////////////////////////////////
// LICENSE
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// COPYRIGHT (C) 2013 Doulos. All rights reserved.

////////////////////////////////////////////////////////////////////////////////
// DECLARATION
class Mutex;
  // timeout of zero (0) means no limit
  extern function new(time timeout=0); //< timeout establishes default
  extern task lock(time timeout = 0);
  extern function void unlock();
  extern function bit  try_lock();
  extern function bit  is_locked();
  extern function bit  is_owned();
  local static int  s_errors = 0;
  static function int errors(); return s_errors; endfunction
  event  locked, unlocked;
// Private data
  local std::semaphore m_mutex;
  local std::process   m_locked;
  local time           m_timeout;
endclass

////////////////////////////////////////////////////////////////////////////////
// IMPLEMENTATION

`ifndef MUTEX_ERROR
`define MUTEX_ERROR(message,lno=`__LINE__)\
   $display("%0t: %s(%0d) MUTEX ERROR: %s",$time,`__FILE__,lno,message)
`endif
// Compiler independent control of immediate assertions -- does NOT handle 'else' clause
`ifndef NASSERT
`define ASSERT(expr,message,lno=`__LINE__) \
   if(!(expr)) $display("%0t: %s(%0d) ASSERT ERROR: NOT %s",$time,fnam,lno,message)
`else
`define ASSERT(expr,message,lno=0)
`endif

function Mutex::new(time timeout);
  m_mutex = new(1);
  m_locked = null;
  m_timeout = timeout;
endfunction

task Mutex::lock(time timeout);
  if (timeout == 0 && m_timeout != 0) timeout = m_timeout;
  if (is_owned()) begin
    `MUTEX_ERROR("Attempt to lock mutex that is already owned -- ignored");
    ++s_errors;
  end
  else begin
    TIMEOUT: fork
      m_mutex.get(1);
      begin
        if (timeout ==0) wait(0); //< wait forever
        else #(timeout) begin 
          `MUTEX_ERROR("Mutex timed out");
          ++s_errors;
        end
      end
    join_any
    disable TIMEOUT;
  end
  m_locked = std::process::self();
  ->locked;
endtask

function bit Mutex::try_lock();
  if (is_owned()) begin
    `MUTEX_ERROR("Attempt to lock mutex that is already owned -- ignored");
    ++s_errors;
  end
  else if (m_mutex.try_get()) begin
    m_locked = std::process::self();
    ->locked;
  end
  return is_owned();
endfunction

function void Mutex::unlock();
  if (!is_owned())
  begin
    `MUTEX_ERROR("Attempt to unlock mutex that is not owned -- ignored");
    ++s_errors;
    return;
  end
  m_mutex.put(1);
  m_locked = null;
  ->unlocked;
endfunction

function bit Mutex::is_locked();
  return (m_locked != null);
endfunction

function bit Mutex::is_owned();
  return (m_locked == std::process::self());
endfunction

////////////////////////////////////////////////////////////////////////////////
//
//  ##### #     #    #    #     # #####  #     ##### 
//  #      #   #    # #   ##   ## #    # #     #     
//  #       # #    #   #  # # # # #    # #     #     
//  #####    #    #     # #  #  # #####  #     ##### 
//  #       # #   ####### #     # #      #     #     
//  #      #   #  #     # #     # #      #     #     
//  ##### #     # #     # #     # #      ##### ##### 
//
//==============================================================================
// EXAMPLE & SELF-TEST

`ifdef UNIT_TEST
module mutex_test;

  const time maxlock = 100ns;
  Mutex m = new(maxlock);
  string fnam = "mutex.sv";

  task grab(string process,time delay, int lno);
    $display("%0t: %s(%0d) %s attempting to lock for %0d",$time,fnam,lno,process,delay);
    m.lock();
    $display("%0t: %s(%0d) %s owns",$time,fnam,lno,process);
    #(delay);
    $display("%0t: %s(%0d) %s releasing",$time,fnam,lno,process);
    m.unlock();
  endtask

  initial begin : PROCESS_1
    static string me = "PROCESS_1";
    @(m.locked);
    `ASSERT(m.is_locked(),"m.is_locked()");
    forever grab(.process(me),.delay(10ns),.lno(`__LINE__));
  end : PROCESS_1

  initial begin : PROCESS_2
    static string me = "PROCESS_2";
    $display("%0t: %s locking",$time,me);
    m.lock();
    $display("%0t: %s locked",$time,me);
    `ASSERT(m.is_owned,"m.is_owned");
    `ASSERT(m.is_locked,"m.is_locked");
    #5ns;
    $display("%0t: %s unlocking",$time,me);
    m.unlock();
    #21ns; //< no contention during other lock
    grab(.process(me),.delay(10ns),.lno(`__LINE__));
    grab(.process(me),.delay(10ns),.lno(`__LINE__));
    #2ns;
    $display("%0t: %s improper attempt to unlock",$time,me);
    m.unlock();
    `ASSERT(Mutex::errors() == 1,"Mutex::errors() == 1");
    $display("%0t: %s locking",$time,me);
    m.lock();
    #20ns;
    $display("%0t: %s improper attempt to re-lock",$time,me);
    m.lock();
    `ASSERT(Mutex::errors() == 2,"Mutex::errors() == 2");
    $display("%0t: %s improper attempt to re-try_lock",$time,me);
    void'(m.try_lock);
    `ASSERT(Mutex::errors() == 3,"Mutex::errors() == 3");
    #5ns;
    $display("%0t: %s unlocking",$time,me);
    m.unlock();
    #10ns;
    @(m.unlocked);
    `ASSERT(!m.is_locked(),"!m.is_locked()");
    m.lock();
    #(maxlock+1); //< exceed timeout
    `ASSERT(Mutex::errors() == 4,"Mutex::errors() == 4");
    m.unlock();
    #30ns;
    $stop;
    $display("%0t: %s exiting",$time,me);
    $finish;
  end : PROCESS_2

  final $display("%0t Exited with %0d errors",$time,Mutex::errors());

endmodule
`endif

`endif
//END OF FILE
