--
--  A solution to the Asymmetric traveling salesman problem
--  using pgr_tsp.
--
--  Solution is to rewrite the distance matrix in to inverse copy and
--  link the two copies of a town together by a zero link route.
--
--  See http://en.wikipedia.org/wiki/Traveling_salesman_problem#Solving_by_conversion_to_symmetric_TSP
--  for the details.
--  
--  Note entries need not be in the range 1-N but can be 1,2,42,123 etc.
--
--  DUE to the number of messages generated about temporary tables, chaging the
--  default of PGOPTIONS to ='--client-min-messages=warning' will stop a lot
--  of uncessary error messages

--
--
DROP  type pgr_atsprowtype CASCADE;
CREATE type pgr_atsprowtype as (id integer,seq integer);

--
-- Take an sql string with source,target and cost and a starting node and generate
-- a result set.
--
-- Input
--
-- select seq,id from pgr_mktspret('select source,target,cost from edge5' ,xx);
--
-- Where xx is any node number in the network
--
-- 


CREATE or REPLACE FUNCTION pgr_mkatspret(sqltext text ,startpt integer) 
	RETURNS SETOF pgr_atsprowtype 
AS $$

DECLARE
        matrix double precision [];
	newstartpt integer;
	tmp pgr_atsprowtype%rowtype;
	mat_size integer;
	mat_end_size integer;
	i integer;
	j integer;
	endmat integer [];
	retmat integer [];
BEGIN
	select  datasize,ret_array into mat_size,matrix from pgr_mkatsparray(sqltext) ;
	select pgr_atspname2index  INTO newstartpt from pgr_atspname2index(startpt);

	IF ( newstartpt is null )  THEN
		RAISE EXCEPTION  ' Error Can not find start node % in sql request ',startpt;
	END IF ;

	i := 0;
    	FOR tmp IN  select (pgr_tsp.seq),(pgr_atspindex2name(pgr_tsp.id,mat_size))  FROM pgr_tsp(matrix,newstartpt,newstartpt) LOOP
		endmat[i] := tmp.seq;
    		i := i + 1;
    	END LOOP;


	mat_end_size := 0;
    	FOR j in 0..((mat_size*2) -1) LOOP 
		IF  endmat[j] = endmat[j+1]   THEN
		 	mat_end_size := mat_end_size;
		ELSE 
		 	retmat[mat_end_size]=endmat[j];
		 	mat_end_size := mat_end_size +1;

		END IF;
    
    	END LOOP;
	FOR j in  0.. mat_end_size-1  LOOP
		tmp.seq :=j+1;
		tmp.id := retmat[j];

		return next tmp;

	END LOOP;

END
$$
LANGUAGE 'plpgsql' VOLATILE;

--
-- Make a distance matrix for the traveling salesman  problem
--
-- Input is an sql string that provides source, target and the cost
-- of getting between them
--
-- 

CREATE or REPLACE FUNCTION pgr_mkatsparray(tag_name text , OUT datasize integer,OUT  ret_array double precision [] ) 
    
    AS $$
DECLARE
        tsp_array float [][];
	array_size integer;
	orginal_size integer;
	atsp_details record;
	s integer;
	t integer;
	lookupi integer;
	lookupj integer;
BEGIN

        ret_array := array[]::double precision[]; 
	-- create a copy of the source
	EXECUTE 'DROP TABLE IF EXISTS pgr_atsp_src';
	EXECUTE 'DROP TABLE IF EXISTS pgr_atsp_map';


	create temporary table pgr_atsp_src ( id serial not null,source integer not null, 
  				target integer not null,  cost float not null);
	-- create a pgr_atsp node to matrix lookup table
  	create temporary table pgr_atsp_map ( id serial not null primary key, nid integer);

        EXECUTE 'insert into pgr_atsp_src (source, target, cost) '|| tag_name;
	-- ensure that source to target has a cost of zero and ensure that this cost exists
        insert into pgr_atsp_map (nid) select nid from (select distinct source as nid from pgr_atsp_src union select distinct target as nid from pgr_atsp_src  ) as foo ;
	
	select count(*) INTO orginal_size from pgr_atsp_map;
	
	datasize := orginal_size;
  	
	-- should generate a matrix count(*) X count(*) of pgr_atsp_map
	select pgr_mktsparray  into tsp_array from pgr_mktsparray(orginal_size,'select source, target,cost from pgr_atsp_src ');

	-- by default populate the return results with zero, so any unknown
	-- routes will not be listed
	array_size := orginal_size * 2;
	-- default entry very expensive ie do not route this way
	ret_array :=array_fill(9999999,ARRAY	[ array_size,array_size]);

	FOR t in 1..orginal_size LOOP  -- source
		FOR s in 1..orginal_size LOOP       -- target 
			ret_array[t+orginal_size][s]=tsp_array[t][s];
			ret_array[s][t+orginal_size]=tsp_array[t][s];

		END LOOP;
 	END LOOP; 

	FOR t in 1..orginal_size LOOP  -- source
		ret_array[orginal_size+t][t]=0;
		ret_array[t][t+orginal_size]=0;

	END LOOP; 
END
$$
LANGUAGE 'plpgsql' STRICT;


--
-- Lookup a internal network number and convert it to a user number 
--
CREATE or REPLACE FUNCTION pgr_atspindex2name(integer,integer) RETURNS integer AS 
$$
DECLARE
	userid alias for $1;
	mat_size alias for $2;
	ouserid integer;
	ret integer;
BEGIN
	ouserid= userid;
	IF ( userid+1 > mat_size ) THEN
		userid := userid - mat_size;
	END IF ;
 	select nid  from pgr_atsp_map where id= userid +1 INTO ret ;
	raise notice 'Old % New % lookup %',
		ouserid,userid,ret;
	return ret;
END
$$
LANGUAGE 'plpgsql';

--
-- Lookup a user network convert and convert it to an internal matrix number
--
CREATE or REPLACE FUNCTION pgr_atspname2index(integer) RETURNS integer AS 
$$
DECLARE
	userid alias for $1;

	ret integer;
BEGIN
	
 	select id  from pgr_atsp_map where nid= userid INTO ret ;
	return ret-1;
END
$$
LANGUAGE 'plpgsql';