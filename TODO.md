- how easy would it be to have a single game implementation support multiple games sessions instead of a single one? I'm a bit divided whether a single game server should support multple game sessions in parallel. I guess it depends on how may sources a single game server takes

- let's devise an additional lisp component sitting alongside the game servers which will handle persistence of user related state and authentication. it should support queries of where is player x (which game, which session). is should support game servers setting those values. it should support game servers reading user-related info and saving changes atomically (ie, multiple concurrent changes shouldn't break it). user related things should default to memory but be lazily persisted to disk in case of the component failing to be able to resume

- i would like to support authentication. could be email one time token and/or google authetntication (can i support google auth without registering my domain somehow with them?)

- not all games need client side prediction. support a simple setup for some games where server is authoritative period (maybe there's nothing to change on the server, just keep the client simpler). I want to illustrate this idea with 1 or 2 simple games, such as tictactoe and a simple cards game (where hidden state is involved, ie, different clients get server differnt parts of the state

- it would be great if scaling of game servers would depend on requests. this would require the gateway to be able to know which ip/port of game servers would be online and how many clients each has (updated periodically)
