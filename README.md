# Pseudonym Pairs: a proof-of-unique-human system

Pseudonym Pairs is a coordination game for global proof-of-unique-human, through monthly pseudonym events that last 15 minutes, where every single person on Earth is randomly paired together with another person, 1-on-1, to verify that the other is a human being, in a pseudo-anonymous context. _The proof-of-unique-human is that you are with the same person for the whole event._ The proof-of-unique-human is untraceable from month to month, much like cash. True anonymity.

![](https://camo.githubusercontent.com/a9872931c4331a31da92e4e1db3c82eec6af7543/68747470733a2f2f692e696d6775722e636f6d2f687266796f6b322e706e67)

# Implementation

The Pseudonym Pairs system is built around the functions `register()`, `immigrate()`, `dispute()` and `reassign()`. The schedule is enforced with `scheduler()`. Personhood is verified with the public mapping `proofOfPersonhood`. Mixing is done with external contracts. Incredibly simple.

For a complete reference implementation, see [PseudonymPairs.sol](https://gist.github.com/0xAnonymous/8d93d20ac056b45e2ba2d5455cc2024b).

# Game theory
Verification in the pairs requires both people to verify one another. The system is built around a general dispute mechanism, `dispute()`, that breaks up a pair and subordinates both peers each under another pair, that acts as a form of court. The peers under these "courts" have to be verified by both people in the pair, 2-on-1. _This mechanism makes it possible to use pairs as the standard mode of operation._ The same court validation is also used when opting-in or "immigrating" to the network (using `immigrate()`), the immigrant is subordinated another pair. That immigration requires people to pass a form of "virtual border" is the basis for how the network prevents bots (as in, fake accounts. )

# Attack vectors

The only problematic attack vector is collusion attacks. It cannot be fully prevented, and the protocol assumes some minor collusion attacks will be a constant factor. They scale with an inverse square relationship, and the payoff is minimal unless a significant part of the population colludes. The pairs the colluders gains control of can be calculated with how many pairs they get majority in (both people in. ) Mathematically this is (colluders/population)^2, based on probability theory. The colluders control these pairs without a human appearing in event, which means they can simultaneously be verified at the border with the people assigned to those pairs.

The bots controlled and overall people that are free to be verified at the border increases slightly with repeated attacks, but there is less and less increase for each round. The benefit of repeated attacks can be calculated with the recursive sequence bots_n = ((colluders + population * bots_{n-1})/(population + population * bots_{n-1}))^2 and it plateaus very close to (colluders/population)^2.

Then, there is the perfectly defendeable attack vector "man in the middle attack". This attack requires a defense protocol. There are many approaches and the attack vector can be defended entirely. For one example, see [ManInTheMiddle.md](https://github.com/0xAnonymous/pseudonympairs.tech/blob/master/ManInTheMiddleAttack.md).
