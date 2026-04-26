## Goal

The goal is to design and deliver a state machine library in elixir. Precisely, a [finite state machine](https://en.wikipedia.org/wiki/Finite-state_machine).

We want to support all the common state machine operations i.e.:

* definition of states including initial and final states
* definition of events and transitions they cause between the different states
  * including guards and side effects for such transitions
* we should allow accruing more state than just the "state" (i.e. for the classical vending machine example you need a counter for how much money is in there etc.)
  * this state should probably be a part of the "current" instance of the state machine
* ecto support is for a successful future (as in, this is useful to me and others), and probably as a separate sister library

The design should focus on:
* data, i.e. at best both the state machine definition and the current state of the state machine are pieces of data tha can be passed around, updated and introspected
* --> no macros, much like [benchee](https://github.com/bencheeorg/benchee) I want to push data and functions as far as possible, a separate library could build a macro layer above it, if it wanted
* should enable features like generating mermaid diagrams from a state machine definition easily, as we have the state machine definitions readily available as data structures
* process agnostic - you could use it from a process, but it's not tied to a process, it's just data - this is one of the main reasons for creating this library as `gen_statem` that ships with the standard library is always bound to a process

Through convenience functions, ability of the structure to generate diagrams, a better overview of possible states, events & more we want to be better than "just data structures, function heads and pattern matching".

## Prior Art
* [gen_statem](https://www.erlang.org/doc/apps/stdlib/gen_statem.html) - part of the erlang standard library, but tied to a process (more [high level docs](https://www.erlang.org/doc/system/statem.html))
* [state_machine](https://github.com/youroff/state_machine), elixir, uses macros heavily but looks cool
* [fsm](https://github.com/sasa1977/fsm), elixir, by Saša, heavy on macros, mentioning in the deprecation notice that pure data structures with pattern matches will serve you just fine
* [aasm](https://github.com/zven21/aasm), elixir, not maintained any more, based on Ruby's aasm (which I also used to use)
* [ecto_state_machine](https://github.com/asiniy/ecto_state_machine), elixir, unmaintained, uses macros as well - but the definition of a state machine looks a lot like what I'd imagine we'd eventually end up with (i.e. pure data)
* [fsmx](https://github.com/subvisual/fsmx), elixir, hasn't seen an update in 3 years, looks really solid though, but doesn't seem to care about events just states, provides a lot of guidance around side effects
* [ash_state_machine](https://github.com/ash-project/ash_state_machine), elixir, of course ash has a state machine implementation
* [xstate](https://github.com/statelyai/xstate), TypeScript, seems to be popular and state machines are a central part of that, it does the full statecharts though
* [finite_machine](https://github.com/piotrmurach/finite_machine), ruby, a well documented library
* [aasm](https://github.com/aasm/aasm), ruby, the OG library I used to use

There is a [nice overview of state machines and libraries implementing them](https://github.com/leonardomso/awesome-fsm).
