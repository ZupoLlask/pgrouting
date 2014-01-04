
--  pgRouting 2.0 types


CREATE TYPE pgr_costResult AS
(
    seq integer,
    id1 integer,
    id2 integer,
    cost float8
);

CREATE TYPE pgr_costResult3 AS
(
    seq integer,
    id1 integer,
    id2 integer,
    id3 integer,
    cost float8
);

CREATE TYPE pgr_geomResult AS
(
    seq integer,
    id1 integer,
    id2 integer,
    geom geometry
);

CREATE TYPE pgr_atsprowtype AS
(
	id integer,
	seq integer
);

CREATE TYPE pgr_tsprowtype AS
(
	id integer,
	seq integer
);
