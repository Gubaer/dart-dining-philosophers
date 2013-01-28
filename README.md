# Dining philosophers

This repository provides various implementations of the
[dining philosopher problem](http://en.wikipedia.org/wiki/Dining_philosophers_problem).

The solutions are implemented in [Dart](http://www.dartlang.org) using Dart's
_isolates_, an actor-like facility for concurrent programming.

The following implementations are  "standard solutions":

 *  [bin/dinner5.dart](https://github.com/Gubaer/dart-dining-philosophers/blob/master/lib/dinner5.dart)
     implements a simulation of a philosopher conference using
    Dijkstra's aproach of [resource ordering] (http://en.wikipedia.org/wiki/Dining_philosophers_problem#Resource_hierarchy_solution).
       
    ```bash
    # run a conference with 5 philosophers 
    $ dart bin/dinner5.dart -n 5
    ```
 
 *  [bin/dinner4.dart](https://github.com/Gubaer/dart-dining-philosophers/blob/master/lib/dinner4.dart) 
    implements a simulation of a philosopher conference using
    the [algorithm of Chandy/Misra] (http://www.cs.utexas.edu/users/misra/scannedPdf.dir/DrinkingPhil.pdf).
    
    ```bash
    # run a conference with 5 philosophers 
    $ dart bin/dinner4.dart -n 5
    
    # to see a log of the eating philosophers
    $ dart bin/dinner4.dart -n 5 | grep "eating"
    philosopher 0: eating ... START
	philosopher 0: eating ... END
	philosopher 2: eating ... START	
	philosopher 2: eating ... END
	...
    ```
    
The other simulations are ad-hoc implementations.

## Streams or Ports?

As of M3 (2013/01) Dart supports two techniques to communicate between
isolates:
  1. **Ports**  - the message source sends a messages to a 
     [SendPort](http://api.dartlang.org/docs/bleeding_edge/dart_isolate/SendPort.html).
     It is received by the message target by a 
     [ReceivePort] (http://api.dartlang.org/docs/bleeding_edge/dart_isolate/ReceivePort.html).
     
  2. **Streams** - the message source adds a message to an
     [IsolateSink](http://api.dartlang.org/docs/bleeding_edge/dart_isolate/IsolateSink.html).
     The message receiver listens on a corresponding 
     [IsolateStream](http://api.dartlang.org/docs/bleeding_edge/dart_isolate/IsolateStream.html). 

Both techniques are used in these examples:
  * [dinner 5](https://github.com/Gubaer/dart-dining-philosophers/blob/master/lib/dinner5.dart)
    simulates a dinner of philosophers using **ports**
    
  * [dinner 6](https://github.com/Gubaer/dart-dining-philosophers/blob/master/lib/dinner6.dart)
    simulates a dinner of philosophers using **streams**
      

## Notes
*  The simulations reveal limitations with Dart's current (2013/01, pre Dart M3) 
   actor implementation.
   It seems that the Dart VM is currently limited to ~ 100 actors.  
   For instance,
   ```
   $ dart bin/dinner5.dart -n 50
   ```
   which creates an actor graph for 50 philosophers and 50 forks currently 
   terminates with a `Segmentation fault`.


