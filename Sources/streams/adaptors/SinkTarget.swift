//
//  SinkTarget.swift
//  Noze.IO
//
//  Created by Helge Hess on 30/06/15.
//  Copyright © 2015 ZeeZide GmbH. All rights reserved.
//

import Dispatch

public protocol SinkType { // 2beta4 has no SinkType anymore
  
  associatedtype Element
  
#if swift(>=3.0)
  mutating func put(_ x: Self.Element)
#else
  mutating func put(x: Self.Element)
#endif
}

public struct SyncSinkTarget<S: SinkType> : GWritableTargetType {
  
  public static var defaultHighWaterMark : Int { return 1 }
  
  var target : S
  
  // MARK: - Init from a GeneratorType or a SequenceType
  
  public init(_ target: S) {
    self.target = target
  }

  private mutating func _writev(chunks : [ [ S.Element ] ]) -> Int {
    var count = 0
    
    for bucket in chunks {
      for value in bucket {
        self.target.put(value)
        count = count + 1
      }
    }
    return count
  }
  
  public mutating func writev(queue q : dispatch_queue_t,
                              chunks  : [ [ S.Element ] ],
                              yield   : ( ErrorType?, Int ) -> Void)
  {
#if swift(>=3.0) // #swift3-1st-kwarg
    let count = _writev(chunks: chunks)
#else
    let count = _writev(chunks)
#endif
    yield(nil, count)
  }
}

private func getDefaultWorkerQueue() -> dispatch_queue_t {
  /* Nope: Use a serial queue, w/o internal synchronization we would generate
           yields out of order.
  return dispatch_get_global_queue(QOS_CLASS_DEFAULT,
                                   UInt(DISPATCH_QUEUE_PRIORITY_DEFAULT))
  */
  return dispatch_queue_create("io.noze.target.sink.async", nil)
}

public class ASyncSinkTarget<S: SinkType> : GWritableTargetType {
  // TODO: almost a dupe of ASyncGeneratorSource, any way to somehow DRY? :-)
  
  public static var defaultHighWaterMark : Int { return 1 }
  
  var target              : S
  let workerQueue         : dispatch_queue_t
  let maxCountPerDispatch : Int
  
  // MARK: - Init from a GeneratorType or a SequenceType
  
  public init(_ target            : S,
              workerQueue         : dispatch_queue_t = getDefaultWorkerQueue(),
              maxCountPerDispatch : Int = 16)
  {
    self.target              = target
    self.workerQueue         = workerQueue
    self.maxCountPerDispatch = maxCountPerDispatch
  }
  
  /// Asynchronously generate items.
  ///
  /// This dispatches the generator on the workerQueue of the source, but
  /// properly yields back results on the queue which is passed in.
  ///
  /// The number of generation attempts can be limited using the
  /// maxCountPerDispatch property. I.e. that property presents an upper limit
  /// to the 'count' property which was passed in.
  public func writev(queue Q : dispatch_queue_t,
                     chunks  : [ [ S.Element ] ],
                     yield   : ( ErrorType?, Int ) -> Void)
  {
    // Note: we do capture self for the sink ...
    let maxCount = self.maxCountPerDispatch
    
    dispatch_async(workerQueue) {
#if swift(>=3.0) // #swift3-1st-kwarg
      let count = self._writev(chunks: chunks, maxCount)
#else
      let count = self._writev(chunks, maxCount)
#endif
      
      dispatch_async(Q) { yield(nil, count) }
    }
  }
  
  private func _writev(chunks : [ [ S.Element ] ], _ maxCount : Int) -> Int {
    var count = 0

    for bucket in chunks {
      for value in bucket {
	self.target.put(value)
	count += 1

	if count >= maxCount {
	  break
	}
      }
    }
    
    return count
  }
}
