# A parser is a value with the following type:
#   type Parser a = (String, Int, Int) -> Maybe (a, Int, Int)
#
# - The parameters are the source, the offset, and the length
# - The result is the value produced, the new offset, and the new length
# - If a failure occurs, the result will be 'null'

with builtins;

with rec {
  # Redefine foldr here to avoid depending on lib
  foldr = op: nul: list:
    let
      len = length list;
      fold' = n:
        if n == len
        then nul
        else op (elemAt list n) (fold' (n + 1));
    in fold' 0;
};

rec {
  # running {{{

  # Run a parser, returning the result in a single-element list, or 'null' if it
  # failed. This is to disambiguate between failing and suceeding with 'null'.
  #
  # If the parser did not consume all of its input, this will still succeed. If
  # you want to make sure all input has been consume, use 'eof'.
  #
  #   :: Parser a -> String -> [a]
  runParser = parser: str:
    let res = parser [str 0 (stringLength str)];
    in if failed res then [] else [(elemAt res 0)];

  # Did a parser fail?
  #   :: Maybe (a, Int, Int) -> Bool
  failed = ps: ps == null;

  # }}}

  # queries {{{

  # Query the current state of the parser
  #   :: Parser (String, Int, Int)
  state = ps:
    let
      offset = elemAt res 1;
      len = elemAt res 2;
    in [ps offset len];

  # Augment a parser to also return the number of characters it consuemd
  tally = parser: ps:
    let
      initialOffset = elemAt ps 1;
      res = parser ps;
    in if failed res
      then null
      else let
        value = elemAt res 0;
        newOffset = elemAt res 1;
        newLength = elemAt res 2;
      in [[(newOffset - initialOffset) value] newOffset newLength];

  # }}}

  # composition {{{

  # Map a function over the result of a parser
  #   :: (a -> b) -> Parser a -> Parser b
  fmap = f: parser: ps:
    let
      res = parser ps;
      val = elemAt res 0;
      offset = elemAt res 1;
      len = elemAt res 2;
    in if failed res
      then null
      else [(f val) offset len];

  # Lift a value into a parser
  #   :: a -> Parser a
  pure = x: ps: [x (elemAt ps 1) (elemAt ps 2)];

  # Monadic bind; sequence two parsers together
  #   :: Parser a -> (a -> Parser b) -> Parser b
  bind = parser: f: ps:
    let
      str = elemAt ps 0;
      res1 = parser ps;   # run the first parser
    in if failed res1
      then null
      else let
        val = elemAt res1 0;
        offset = elemAt res1 1;
        len = elemAt res1 2;
      in (f val) [str offset len];

  # Sequence two parsers, ignoring the result of the first one
  #   :: Parser a -> Parser b -> Parser b
  skipThen = parser1: parser2: bind parser1 (_: parser2);

  # Sequence two parsers, ignoring the result of the second one
  #   :: Parser a -> Parser b -> Parser a
  thenSkip = parser1: parser2: bind parser1 (x: fmap (_: x) parser2);

  # }}}

  # options and failure {{{

  # Parser that always fails (the identity under 'alt')
  #   :: Parser a
  fail = _: null;

  # Run two parsers; if the first one fails, run the second one
  #   :: Parser a -> Parser a -> Parser a
  alt = parser1: parser2: ps:
    let
      str = elemAt ps 0;
      res1 = parser1 ps;
      res2 = parser2 ps;
    in if failed res1 then res2 else res1;

  # Try to apply a parser, or return a default value if it fails without
  # consuming input
  #   :: a -> Parser a -> Parser a
  option = def: parser: alt parser (pure def);

  # Try to apply a parser. If it succeeds, return its result in a singleton
  # list, and if it fails without consuming input, return an empty list
  #   :: Parser a -> Parser [a]
  optional = parser: alt (fmap (x: [x]) parser) (pure []);

  # Run a list of parsers, using the first one that succeeds
  #   :: [Parser a] -> Parser a
  choice = foldr alt fail;

  # }}}

  # consumption primitives {{{

  # Consumes a character if it satisfies a predicate
  #   :: (Char -> Bool) -> Parser Char
  satisfy = pred: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
      c = substring offset 1 str; # the next character
    in if len > 0 && pred c
      then [c (offset + 1) (len - 1)]
      else null;

  # Consumes a character if it satisfies a predicate, applying a function to the
  # result.
  #   :: (Char -> a) -> (Char -> Bool) -> Parser a
  satisfyWith = f: pred: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
      c = substring offset 1 str; # the next character
    in if len > 0 && pred c
      then [(f c) (offset + 1) (len - 1)]
      else null;

  # Consume any character
  #   :: Parser Char
  anyChar = satisfy (_: true);

  # Consume any character except a given character
  #   :: Char -> Parser Char
  anyCharBut = c: satisfy (x: x != c);

  # Given a string, try to consume it from the input and return it if it
  # suceeds. If it fails, DON'T consume any input.
  #   :: String -> Parser String
  string = pr: ps:
    let
      prefixLen = stringLength pr;
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if len >= prefixLen && substring offset prefixLen str == pr
      then [pr (offset + prefixLen) (len - prefixLen)]
      else null;

  # 'notFollowedBy p' only succeeds when 'p' fails, and never consumes any input
  #   :: Parser a -> Parser null
  notFollowedBy = parser: ps:
    let
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if failed (parser ps)
      then [null offset len]
      else null;

  # Fails if there is still more input remaining, returns null otherwise
  #   :: Parser null
  eof = ps:
    let
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if len == 0
      then [null offset len]
      else null;

  # }}}

  # takes {{{

  # Consume 'n' characters, or fail if there's not enough characters left.
  # Return the characters consumed.
  #   :: Int -> Parser String
  take = n: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if n <= len
      then [(substring offset n str) (offset + n) (len - n)]
      else null;

  # Consume characters while the predicate holds, returning the consumed
  # characters
  #   :: (Char -> Bool) -> Parser String
  takeWhile = pred: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
      # Search for the next offset that violates the predicate
      go = ix:
        if ix >= len || !pred (substring ix 1 str)
          then ix
          else go (ix + 1);
      endIx = go offset;
      # The number of characters we found
      numChars = endIx - offset;
    in [(substring offset numChars str) endIx (len - numChars)];

  takeWhile1 = null;

  # Apply a parser zero or more times until it fails, returning a list of the
  # results
  #   :: Parser a -> Parser [a]
  many = parser:
    let go = alt (bind parser (first: fmap (rest: [first] ++ rest) go)) (pure []);
    in go;

  # Apply a parser one or more times until it fails, returning a list of the
  # resuls
  #   :: Parser a -> NonEmpty a
  many1 = parser:
    bind parser (first: fmap (rest: [first] ++ rest) (many parser));

  manyTill = null;

  # }}}

  # skips {{{

  # Consume 'n' characters, or fail if there's not enough characters left.
  #   :: Int -> Parser null
  skip = n: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if n <= len
      then [null (offset + n) (len - n)]
      else null;

  # Consume characters while the predicate holds
  #   :: (Char -> Bool) -> Parser null
  skipWhile = pred: ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
      # Search for the next offset that violates the predicate
      go = ix:
        if ix >= len || !pred (substring str ix 1)
          then ix
          else go (ix + 1);
      endIx = go offset;
      # The number of characters we found
      numChars = endIx - offset;
    in [null endIx (len - numChars)];

  skipWhile1 = null;

  skipMany = null;

  skipMany1 = null;

  # }}}

  # peeks and drops {{{

  # Examine the next character without consuming it. Fails if there's no input
  # left.
  #   :: Int -> Parser String
  peek = ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in if len > 0
      then [(substring offset 1 str) offset len]
      else null;

  # Examine the rest of the input without consuming it
  #   :: Parser String
  peekRest = ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in [(substring offset len str) offset len];

  # Consume and return the rest of the input
  #   :: Parser String
  consumeRest = ps:
    let
      str = elemAt ps 0;
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in [(substring offset len str) (offset + len) 0];

  # Consume and ignore the rest of the input
  #   :: Parser null
  dropRest = ps:
    let
      offset = elemAt ps 1;
      len = elemAt ps 2;
    in [null (offset + len) 0];

  # }}}

  # combinators {{{

  # Sequence three parsers, 'before', 'after', and 'middle', running them in the
  # obvious order and keeping the middle result.
  # Example: parens = between (string "(") (string ")")
  #
  #   :: Parser a -> Parser b -> Parser c -> Parser c
  between = before: after: middle: skipThen before (thenSkip middle after);

  # Repeat a parser 'n' times, returning the results from each parse
  #   :: Int -> Parser a -> Parser [a]
  replicate = n: parser:
    let go = m: if m == 0
      then pure []
      else bind parser (first: fmap (rest: [first] ++ rest) (go (m - 1)));
    in go n;

  # }}}
}

# vim: foldmethod=marker: