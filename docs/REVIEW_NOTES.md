# Review notes on the legacy contracts

These are flags raised while reading `legacy/v0/`. They are not confirmed bugs. Each needs a test or a decision.

1. EMA price: the first poke seeds the average without the clamp. Check that a manipulated first observation cannot set a bad baseline.
2. A comment compares B/S with (B+1)/(S+V). Confirm which formula the code actually uses and fix the comment or the code.
3. `_fitBuy` bounds the buy using spot (slot0), which can be moved within a transaction. The EMA bound is the real protection, so confirm it always applies.
4. Gas: a private sale costs about 4.7M to 5.2M gas. This may exceed public bundler limits.
5. Asset field: `Sale` and `onPrivateExit` need an asset field. `IExitTarget` draft v2 adds it.
