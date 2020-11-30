-- Create a BBL-level view with indicators of displacement risk for all
-- building with 3 or more units. We use a materialized view so that we can
-- easily create a trigger to refresh the view anytime new data is available
DROP MATERIALIZED VIEW IF EXISTS ridgewood.hdc_building_info CASCADE;
CREATE MATERIALIZED VIEW ridgewood.hdc_building_info AS (
	-- PLUTO
	----------------------------
	-- Get all BBLs with 3+ units, create point geometry. This universe of BBLs
	-- is the starting point to join all other information on
	WITH pluto as (
	SELECT
		p.bbl,
		(p.address || ', ' || p.borough || ', NY ' || p.zipcode) AS address,
		p.unitsres AS residential_units,
		p.yearbuilt AS year_built,
		-- use SRID:2263 so we can calculate distance in feet
		ST_Transform(ST_SetSRID(ST_Point(p.lng, p.lat), 4326), 2263) as geom_point 
	FROM pluto_19v2 AS p 
	WHERE p.unitsres >= 3
	), 

	-- HPD Violations
	----------------------------
	-- For each BBL get an indicator of the presence of any HPD Violations since
	-- 2019, and a list of all apartment numbers if available.
	hpd_viol as (
	SELECT
		bbl,
	  	SUM((class = 'A')::int) AS hpd_viol_a_num,
	  	SUM((class = 'B')::int) AS hpd_viol_b_num,
	  	SUM((class = 'C')::int) AS hpd_viol_c_num
	FROM hpd_violations
	WHERE inspectiondate >= '2019-01-01'
	GROUP BY bbl
	), 

	-- HPD Complaints
	----------------------------
	-- For each BBL get an indicator of the presence of any HPD Complaints since
	-- 2019, and a list of all apartment numbers if available.
	hpd_comp as (
	SELECT
		bbl,
	  	SUM((type = 'NON EMERGENCY')::int) AS hpd_comp_nonemerg_num,
	  	SUM((type = 'EMERGENCY')::int) AS hpd_comp_emerg_num,
	  	SUM((type = 'IMMEDIATE EMERGENCY')::int) AS hpd_comp_immedemerg_num,
	  	SUM((type = 'HAZARDOUS')::int) AS hpd_comp_haz_num,
		regexp_replace(
			array_to_string(array_agg(DISTINCT apartment), ', '),
			'(BLDG,\s)|(BLDG$)|(,\sBLDG)', ''
		) AS hpd_comp_apts
	FROM hpd_complaints AS c
	LEFT JOIN hpd_complaint_problems AS cp USING(complaintid)
	WHERE receiveddate >= '2019-01-01'
	GROUP BY bbl
	), 

	-- DOB Complaints
	-----------------
	-- For each BBL get the date of the most recent DOB Complaint for illegal SRO
	-- (single room occupancy) conversion (These can potentially become defacto
	-- rent stabilized if they they have 6+ units and built before 1974, even if
	-- the units aren't legal)

	-- TODO: is there other stuff from dob complaints to include?
	dob_comp as (
	SELECT 
		bbl,
		max(inspectiondate) AS dob_comp_sro_latest
	FROM dob_complaints AS dob
	-- DOB complaints doesn't have bbl, so we need to join it in by BIN from PAD
	INNER JOIN pad_adr AS pad ON dob.bin::char(7) = pad.bin
	-- "SRO – Illegal Work/No Permit/Change In Occupancy Use"
	WHERE complaintcategory = '71' 
	GROUP BY bbl
	),

	-- ECB Violations
	-----------------
	-- Indicator of the presence of any ECB violations for illegal residential
	-- conversions, and some details of the latest violation.
	ecb_viol AS (
	SELECT DISTINCT ON (bbl)
		bbl,
		last(issuedate order by issuedate) AS ecb_viol_sro_issue_latest,
		last(ecbviolationstatus order by issuedate) AS ecb_viol_sro_status,
		last(violationdescription order by issuedate) AS ecb_viol_sro_description
	FROM ecb_violations
	WHERE
		-- NYC Law 28-210.1 Illegal residential conversions.
		sectionlawdescription1	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription2	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription3	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription4	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription5	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription6	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription7	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription8	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription9	~ '(^|\D)28-210\.1(\D|$)' OR
		sectionlawdescription10 ~ '(^|\D)28-210\.1(\D|$)'
	GROUP BY bbl
	),
 	
	-- Marshal Evictions (2017-2019)
	-----------------
	-- For each BBL get the number of residential evictions in each year
 	evic19 AS ( 
 	SELECT 
 		bbl,
		count(*) AS marsh_evic_19_num
	FROM pluto AS p
	INNER JOIN marshal_evictions_19 USING(bbl)
	WHERE residentialcommercialind = 'RESIDENTIAL'
	GROUP BY bbl
	),
 	evic18 AS ( 
 	SELECT 
 		bbl,
		count(*) AS marsh_evic_18_num
	FROM pluto AS p
	INNER JOIN marshal_evictions_18 USING(bbl)
	WHERE residentialcommercialind = 'Residential'
	GROUP BY bbl
	),
 	evic17 AS ( 
 	SELECT 
 		bbl,
		count(*) AS marsh_evic_17_num
	FROM pluto AS p
	INNER JOIN marshal_evictions_17 USING(bbl)
	WHERE evictiontype = 'Residential'
	GROUP BY bbl
	),

	dereg AS (
	SELECT 
		bbl,
		uc2019 AS rent_stab_19_units,
	   	(nullif(uc2007, 0) - uc2019) AS dereg_07_19_units,
	   	(nullif(uc2007, 0) - uc2019)::numeric/uc2007 AS dereg_07_19_pct
	FROM rentstab AS rs1
	LEFT JOIN rentstab_v2 AS rs2 USING(ucbbl)
	INNER JOIN pluto AS p ON rs1.ucbbl = p.bbl
	),

	everything as (
		SELECT
			p.bbl,
			p.address,
			p.residential_units,
			p.year_built,

			coalesce(hpd_viol.hpd_viol_a_num, 0) AS hpd_viol_a_num,
			coalesce(hpd_viol.hpd_viol_b_num, 0) AS hpd_viol_b_num,
			coalesce(hpd_viol.hpd_viol_c_num, 0) AS hpd_viol_c_num,

			coalesce(hpd_comp.hpd_comp_nonemerg_num, 0) AS hpd_comp_nonemerg_num,
			coalesce(hpd_comp.hpd_comp_emerg_num, 0) AS hpd_comp_emerg_num,
			coalesce(hpd_comp.hpd_comp_immedemerg_num, 0) AS hpd_comp_immedemerg_num,
			coalesce(hpd_comp.hpd_comp_haz_num, 0) AS hpd_comp_haz_num,
			nullif(trim(hpd_comp_apts), '') AS hpd_comp_apts,

			dob_comp.dob_comp_sro_latest,

			ecb_viol.ecb_viol_sro_issue_latest,
			ecb_viol.ecb_viol_sro_status,
			ecb_viol.ecb_viol_sro_description,

			coalesce(evic19.marsh_evic_19_num, 0) AS marsh_evic_19_num,
			coalesce(evic18.marsh_evic_18_num, 0) AS marsh_evic_18_num,
			coalesce(evic17.marsh_evic_17_num, 0) AS marsh_evic_17_num,

			coalesce(dereg.rent_stab_19_units, 0) AS rent_stab_19_units,
			coalesce(dereg.dereg_07_19_units, 0) AS dereg_07_19_units,
			case
				when dereg.dereg_07_19_pct > 1 then 1
				else coalesce(dereg.dereg_07_19_pct, 0)
			end AS dereg_07_19_pct,

			p.geom_point 

		FROM pluto AS p
		LEFT JOIN hpd_viol USING(bbl)
		LEFT JOIN hpd_comp USING(bbl)
		LEFT JOIN dob_comp USING(bbl)
		LEFT JOIN ecb_viol USING(bbl)
		LEFT JOIN evic19 USING(bbl)
		LEFT JOIN evic18 USING(bbl)
		LEFT JOIN evic17 USING(bbl)
		LEFT JOIN dereg USING(bbl)
	)
	SELECT
		*,
		-- combine all the relevant indicators (with some weighing for importance)
		-- into an index for prioritizing buildings for outreach

		-- TODO: this is just a placeholder until we decide what to use.
		(
			hpd_viol_c_num * 4
			+ hpd_viol_b_num * 3
			+ hpd_viol_a_num * 1
			+ hpd_comp_nonemerg_num * 1
			+ hpd_comp_emerg_num * 2
			+ hpd_comp_immedemerg_num * 3
			+ hpd_comp_haz_num * 4
			+ -- need to account for how recent these are
			+ (dob_comp_sro_latest is not null)::int * 100
			+ (ecb_viol_sro_issue_latest is not null)::int * 100
			+ marsh_evic_19_num * 15
			+ marsh_evic_18_num * 10
			+ marsh_evic_17_num * 5
			+ dereg_07_19_pct * 100
		) * residential_units AS priority_index
	FROM everything
);

CREATE INDEX ON ridgewood.hdc_building_info (bbl);
CREATE INDEX ON ridgewood.hdc_building_info (priority_index);
CREATE INDEX ON ridgewood.hdc_building_info USING GIST (geom_point);


-- Create a function that simply refreshes our materialized view so that we
-- can call this function in the trigger below
DROP FUNCTION IF EXISTS ridgewood.refresh_hdc_building_info() CASCADE;
CREATE OR REPLACE FUNCTION ridgewood.refresh_hdc_building_info()
RETURNS TRIGGER LANGUAGE plpgsql
AS $$
BEGIN
REFRESH MATERIALIZED VIEW CONCURRENTLY ridgewood.hdc_building_info;
RETURN NULL;
END $$;

-- Create a trigger so that anytime there is a change to the hpd_complaints
-- table the materialized view is updated. (since we update all the tables at
-- the same time we can just use any of the tables used in the mat view that
-- are updated on a daily schedule)
CREATE TRIGGER ridgewood.refresh_hdc_building_info
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
ON hpd_violations
FOR EACH STATEMENT
EXECUTE PROCEDURE ridgewood.refresh_hdc_building_info();

-- For a given bbl get the X highest priority buildings within ~X min walk
DROP FUNCTION IF EXISTS ridgewood.get_outreach_bbls_from_bbl(text, integer, integer);
CREATE OR REPLACE FUNCTION ridgewood.get_outreach_bbls_from_bbl(_bbl text, _n integer, _min integer)
RETURNS SETOF ridgewood.hdc_building_info AS $$
	WITH home_bbl AS (
		SELECT geom_point
		FROM ridgewood.hdc_building_info
		WHERE bbl = _bbl
	)
	SELECT bldgs.* 
	FROM ridgewood.hdc_building_info AS bldgs, home_bbl
	-- geom is in 2263 (feet), rough estimate based on 400m=5min walk
	WHERE ST_DWithin(bldgs.geom_point, home_bbl.geom_point, 262.467 * _min)
	ORDER BY priority_index DESC
	LIMIT _n;
$$ LANGUAGE SQL;