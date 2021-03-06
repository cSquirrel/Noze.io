//
//  Lookup.swift
//  NozeIO
//
//  Created by Helge Hess on 11/04/16.
//  Copyright © 2016 ZeeZide GmbH. All rights reserved.
//

import Dispatch
import xsys
import core

#if swift(>=3.0)
  public typealias LookupCB = ( sockaddr_any?, ErrorProtocol? ) -> Void
#else
  public typealias LookupCB = ( sockaddr_any?, ErrorType? ) -> Void
#endif

#if swift(>=3.0) // #swift3-gcd
// Note: we assume that can't fail
let lookupQueue = dispatch_queue_create("io.noze.dns.lookup",
                                        DISPATCH_QUEUE_CONCURRENT)!
#else
let lookupQueue = dispatch_queue_create("io.noze.dns.lookup",
                                        DISPATCH_QUEUE_CONCURRENT)
#endif

/// Perform a DNS lookup using the system facilities.
///
/// Note: This is different to Node in that it directly uses the system types
///       (which integrate nicely into Swift)
///
/// Family is AF_INET4 / AF_INET6
///
public func lookup(domain: String, family: Int32 = xsys.PF_UNSPEC,
                   cb: LookupCB)
{
  core.module.retain()
  
  dispatch_async(lookupQueue) {
    defer { core.module.release() }
    
    var hints = addrinfo()
    hints.ai_family = family
    
    var ptr = UnsafeMutablePointer<addrinfo>(nil)
    defer { freeaddrinfo(ptr) } /* free OS resources (TBD: works with nil?) */
    
    let rc = getaddrinfo(domain, nil, &hints, &ptr)
    guard rc == 0 else {
      nextTick {
        cb(nil, POSIXError(rawValue: rc))
      }
      return
    }
    
    // Does this mean no error, but no result either?
    guard ptr != nil else {
      nextTick {
        cb(nil, nil)
      }
      return
    }
    
    /* copy results - we just take the first match */
#if swift(>=3.0) // #swift3-ptr
    let info   = ptr!.pointee
    let result : sockaddr_any?
    
    if info.ai_addr == nil {
      result = nil // TODO: proper error
    }
    else if info.ai_family == xsys.AF_INET {
      let aiptr = UnsafePointer<sockaddr_in>(info.ai_addr) // cast
      result = sockaddr_any.AF_INET(aiptr!.pointee)
    }
    else if info.ai_family == xsys.AF_INET6 {
      let aiptr = UnsafePointer<sockaddr_in6>(info.ai_addr) // cast
      result = sockaddr_any.AF_INET6(aiptr!.pointee)
    }
    else {
      result = nil // TODO: proper error
    }
#else /* Swift 2.2 */
    let info   = ptr.memory
    let result : sockaddr_any?
    
    if info.ai_addr == nil {
      result = nil // TODO: proper error
    }
    else if info.ai_family == xsys.AF_INET {
      let aiptr = UnsafePointer<xsys_sockaddr_in>(info.ai_addr) // cast
      result = sockaddr_any.AF_INET(aiptr.memory)
    }
    else if info.ai_family == xsys.AF_INET6 {
      let aiptr = UnsafePointer<xsys_sockaddr_in6>(info.ai_addr) // cast
      result = sockaddr_any.AF_INET6(aiptr.memory)
    }
    else {
      result = nil // TODO: proper error
    }
#endif /* Swift 2.2 */
        
    nextTick {
      cb(result, nil)
    }
  }
}

#if swift(>=3.0) // #swift3-1st-arg
public func lookup(_ domain: String, family: Int32 = xsys.PF_UNSPEC,
                   cb: LookupCB)
{
  lookup(domain: domain, family: family, cb: cb)
}
#endif
