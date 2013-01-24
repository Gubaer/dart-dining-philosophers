# Dining philosophers

This repository a couple of solutions for the [dining philosopher problem](http://en.wikipedia.org/wiki/Dining_philosophers_problem).

The solutions are implemented in [Dart](http://www.dartlang.org) using Dart's
_isolates_, an actor-like facility for concurrent programming.

The following implementation is a  "standard solution":

 * `bin/dinner5.dart` implements a simulation of a philosopher conference using
    Dijkstra's aproach of [resource ordering] (http://en.wikipedia.org/wiki/Dining_philosophers_problem#Resource_hierarchy_solution).
    
    Run it using
    ```bash
    # run a conference with 5 philosophers 
    $ dart bin/dinner5.dart -n 5
    ```
    
The other simulations are ad-hoc implementations.

## Notes
*  Most of the simulations in this package are ad-hoc solutions for the 
   dining philosopher problem. The main goal was to
   play around with Dart's concurrency primitives and not to implement one
   of the known standard solutions.
   
*  The simulations reveal limitations with Dart's current (2013/01, pre Dart M3) 
   actor implementation.
   It seems that the Dart VM is currently limited to ~ 100 actors.  
   For instance,
   ```
   $ dart bin/dinner5.dart -n 50
   ```
   which creates an actor graph for 50 philosophers and 50 forks will terminate
   with a `Segmentation fault`.


