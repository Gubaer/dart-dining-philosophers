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

The implementations are based on the Dart SDK 1.6. 

Compared to initial releases of Dart (in particular to the pre 1.0 releases), 
the Dart VM can now cope with larger numbers of isolates. In the current release 1.6
it is perfectly possible to simulate a large conference of philosophers with 
> 100 philosophers. In earlier releases the VM would have crashed in this case 
with a  segmentation violation.


