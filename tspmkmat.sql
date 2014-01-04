--
--  Call the pgroute traveling sales man soultion using an sql string
--  instead of a matrix solution.
--
--  The input is a sql query that returns a source/target nodes  and cost between, the out put
--  is a list of nodes.
--
--    select source,target,cost from route_table
--
--    Were source && target are any integers and cost is a double
--

--  DUE to the number of messages generated about temporary tables, chaging the
--  default of PGOPTIONS to ='--client-min-messages=warning' will stop a lot
--  of uncessary error messages
--
--   version 2.0 Major rewrite to handle asymteric issues.

DROP  type pgr_tsprowtype CASCADE;
CREATE type pgr_tsprowtype as (id integer,seq integer );

--
-- Take an sql string with source,target and cost and a starting node and generate
-- a result set.
--
-- Input 
--
-- select seq,id from pgr_mktspret('select source,target,cost from edge5' ,xx);
--
-- Where xx is any node number in the network,
--  
CREATE or REPLACE FUNCTION pgr_mktspret(sqltext text ,startpt integer) 
	RETURNS SETOF pgr_tsprowtype 

AS $$
DECLARE
	matrix float [][];
	newstartpt integer;
	tmp pgr_tsprowtype%rowtype;
BEGIN

        select pgr_mktsparray INTO matrix from pgr_mktsparray(sqltext) ;
	select pgr_tspname2index  INTO newstartpt from pgr_tspname2index(startpt);

	IF ( newstartpt is null )  THEN
		RAISE EXCEPTION  ' Error Can not find node % in sql request ',startpt;
	END IF ;
	FOR tmp IN  
		select (pgr_tsp.seq),(pgr_tspindex2name(pgr_tsp.id))  from pgr_tsp(matrix,newstartpt) LOOP
		RETURN NEXT tmp;
	END LOOP;
END
$$
LANGUAGE 'plpgsql' VOLATILE;

--
-- Take an sql string with source,target and cost, a size of matrix  and a starting/end node and generate
-- a result set.
--
-- Input 
--
-- select seq,id from pgr_mktspret('select source,target,cost from edge5' ,xx,yy);
--
-- Where xx,yy  is any node number in the network.
--  

CREATE or REPLACE FUNCTION pgr_mktspret(sqltext text ,startpt integer, endpt integer) 
	RETURNS SETOF pgr_tsprowtype 

AS $$
DECLARE
	matrix float [][];
	newstartpt integer;
	newendpt integer;
	tmp pgr_tsprowtype%rowtype;
BEGIN
        select pgr_mktsparray INTO matrix from pgr_mktsparray(sqltext) ;
	select pgr_tspname2index  INTO newstartpt from pgr_tspname2index(startpt);
	select pgr_tspname2index  INTO newendpt from pgr_tspname2index(endpt);

	IF ( newstartpt is null )  THEN
		RAISE EXCEPTION  ' Error Can not find node % in sql request ',startpt;
	END IF ;

	IF ( newendpt is null )  THEN
		RAISE EXCEPTION  ' Error Can not find node % in sql request ',endpt;
	END IF ;

	FOR tmp IN  
		select (pgr_tsp.seq),pgr_tspindex2name(pgr_tsp.id)  from pgr_tsp(matrix,newstartpt,newendpt) LOOP
		RETURN NEXT tmp;
	END LOOP;
END
$$
LANGUAGE 'plpgsql' VOLATILE;

--
-- Make a distance matrix for the traveling salesman  problem
--
-- Input is an sql string that provides source, target and the cost
-- of getting between them.
--
-- Usage is select pgr_mktsparray('select source,target,cost from blah')
--
-- 
CREATE or REPLACE FUNCTION pgr_mktsparray(text) RETURNS float [][]
    
    AS $$
DECLARE
	sql_str alias for $1;
        ret_array float [][];
	tsp_details record;
	i integer;
	j integer;
        array_size integer;
	lookupi integer;
	lookupj integer;
BEGIN

	ret_array := null;
	-- create a copy of the source
	EXECUTE 'DROP TABLE IF EXISTS pgr_tsp_src';
	EXECUTE 'DROP TABLE IF EXISTS pgr_tsp_map';

	create temporary table pgr_tsp_src ( id serial not null,source integer not null, 
				target integer not null,  cost float not null);
	-- create a tsp node to matrix lookup table
	create temporary table pgr_tsp_map ( id serial not null primary key, nid integer);

        EXECUTE 'insert into pgr_tsp_src (source, target, cost)'|| sql_str;
	-- ensure that source to target has a cost of zero and ensure that this cost exists
        insert into pgr_tsp_map (nid) select nid from (select distinct source as nid from pgr_tsp_src union select distinct target as nid from pgr_tsp_src  ) as foo ;
	-- should generate a matrix count(*) X count(*) of pgr_tsp_map

	select round(sqrt(count(*))) from pgr_tsp_src into i;
	select count(*) from pgr_tsp_src into j;
	select count(*) from pgr_tsp_map into array_size;
	--
        -- check that there are enough values to make a square matrix
        --
	IF ( i*i <> j ) THEN
		RAISE EXCEPTION  ' Was expecting square number of parmeters but received only %', j;
	END IF;

	-- by default populate the return results with zero, so any unknown
	-- routes will not be listed
	ret_array :=array_fill(0,ARRAY	[ array_size,array_size]);

	-- Loop trough  the input looking for any listed routes
	FOR tsp_details IN EXECUTE 
			'select  c.id as tar ,
                                 b.id as src,
                                 a.cost as cos
                                from pgr_tsp_src a, pgr_tsp_map b, pgr_tsp_map c
                                where 
					a.source= b.nid and 
					a.target= c.nid and 
					a.cost > 0
					order by b.nid ,c.nid
				  
				' 
	LOOP
  		ret_array[tsp_details.tar][tsp_details.src]:=tsp_details.cos;

	END LOOP;

	
	return ret_array;
END
$$
LANGUAGE 'plpgsql' STRICT;


--
-- Check tsp array
--
-- Check that only the leading diagonal has values of 0.
-- Checks that the array is symmetrical.
-- Checks that zeros do not occur outside of the leading diagonal.
-- Checks that the matrix is Y x Y in size.
-- Is at least 4 elements wide.
--
-- Usage is 
--
-- select * from pgr_checktsparray( '{{0,1,3,3},{1,0,2,2},{3,2,0,2},{3,2,2,0}}'::float8[]);
--
-- return is true or false 
--
CREATE or REPLACE FUNCTION pgr_checktsparray(float [][]) RETURNS boolean  AS
$$
DECLARE 
	userData alias for $1;
	ret boolean;
	lookupi integer;
	lookupj integer;
	array_size integer;
	array_size2 integer;
	
BEGIN


	select array_length (userData,1) into array_size;
  	select array_length (userData,2) into array_size2;
	IF ( array_size <> array_size2 )  THEN
		RAISE WARNING  ' Error in pgr_mktsparray expecting a square matrix size are % X %  ',array_size,array_size2;
		ret:=false;
	END IF;
	IF ( array_size < 4 )  THEN
		RAISE WARNING  'Error in pgr_mktsparray  pgr_tsp requires at least 4 nodes not %',array_size;
		ret:= false;
	END IF;
	ret:= false;

	array_size := array_size ;

	FOR i in 1..array_size LOOP
		FOR j in 1..array_size LOOP

			IF ( i<>j  AND userData[i][j] <= 0 ) THEN
				RAISE WARNING  ' Error in pgr_mktsparray m[%][%] should be more than zero ',i,j;
				return ret;

			END IF ;

			IF ( i = j AND userData[i][j] <> 0 )  THEN

				RAISE WARNING  ' Error in pgr_mktsparray m[%][%] should be zero ',i,j;
				return ret;
			ELSE 
				IF ( userData[i][j] <> userData[j][i] ) THEN
					select pgr_tspindex2name(i) INTO lookupi;
					select pgr_tspindex2name(j) INTO lookupj;
  					RAISE WARNING 'Error in pgr_mktsparray target % source % should be the same as source % target % ',lookupi,lookupj,lookupj,lookupi;
					return ret;

				END IF ;

			END IF ;
		END LOOP;

 	END LOOP;

	ret := true;

	return ret;

END 
$$
LANGUAGE 'plpgsql' STRICT;

--
-- Lookup a internal network number and convert it to a user number 
--
CREATE or REPLACE FUNCTION pgr_tspindex2name(integer) RETURNS integer AS 
$$
DECLARE
	userid alias for $1;

	ret integer;
BEGIN
 	select nid  from pgr_tsp_map where id= userid +1 INTO ret ;
	return ret;
END
$$
LANGUAGE 'plpgsql';

--
-- Lookup a user network conver and convert it to an internal matrix number
--
CREATE or REPLACE FUNCTION pgr_tspname2index(integer) RETURNS integer AS 
$$
DECLARE
	userid alias for $1;

	ret integer;
BEGIN
 	select id  from pgr_tsp_map where nid= userid INTO ret ;
	return ret-1;
END
$$
LANGUAGE 'plpgsql';
