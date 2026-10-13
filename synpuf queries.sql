--Andrew Kilmer: SQL code sample
--Sample queries on data downloaded from 
--https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf/de10-sample-1
--SQL code written in Beekeeper Studio
--NOTE: Results are for demonstration only and do not represent any inference on Medicare population

select '2008' as yr,
  sum(case when "SP_DIABETES"='1' then 1 else 0 end) as diabetes_count,
  count("DESYNPUF_ID") as mem_count,
  1.0*sum(case when "SP_DIABETES"='1' then 1 else 0 end)/count("DESYNPUF_ID") as diabetes_rate
from raw_bene_2008
union
select '2009' as yr,
  sum(case when "SP_DIABETES"='1' then 1 else 0 end) as diabetes_count,
  count("DESYNPUF_ID") as mem_count,
  1.0*sum(case when "SP_DIABETES"='1' then 1 else 0 end)/count("DESYNPUF_ID") as diabetes_rate
from raw_bene_2009
union
select '2010' as yr,
  sum(case when "SP_DIABETES"='1' then 1 else 0 end) as diabetes_count,
  count("DESYNPUF_ID") as mem_count,
  1.0*sum(case when "SP_DIABETES"='1' then 1 else 0 end)/count("DESYNPUF_ID") as diabetes_rate
from raw_bene_2010
order by yr
  
select 'Inpatient' as claim_type, 
  a.total_paid_08,
  b.part_a_mons_08,
  1.0*a.total_paid_08/b.part_a_mons_08 as pmpm_08
from (select sum(cast("CLM_PMT_AMT" as numeric)) as total_paid_08
  from raw_inpatient
  where left("CLM_THRU_DT",4)='2008') a
join (select sum(cast("BENE_HI_CVRAGE_TOT_MONS" as numeric)) as part_a_mons_08
    from raw_bene_2008) b on 1=1

select 'Patient Drug Cost' as claim_type
  ,a.patient_paid_08
  ,b.part_d_mons_08
  ,a.patient_paid_08/b.part_d_mons_08 as patient_rx_pmpm_08
from (select sum(cast("PTNT_PAY_AMT" as numeric)) as patient_paid_08
  from raw_pde
  where left("SRVC_DT",4)='2008') a
join (select sum(cast("PLAN_CVRG_MOS_NUM" as numeric)) as part_d_mons_08
    from raw_bene_2008) b on 1=1

--readmission rate 
--NOTE: this counts ALL 30 day readmissions and does not account for planned readmissions
CREATE TEMP TABLE admits08 AS
select a."DESYNPUF_ID" as member_id,
  a."NCH_BENE_DSCHRG_DT" as discharge_dt,
  min(to_date(b."CLM_ADMSN_DT",'YYYYMMDD')) as readmit_dt
from raw_inpatient a
  left join raw_inpatient b
  on a."DESYNPUF_ID"=b."DESYNPUF_ID"
  and to_date(b."CLM_ADMSN_DT", 'YYYYMMDD') between 
    to_date(a."NCH_BENE_DSCHRG_DT", 'YYYYMMDD')+1 and to_date(a."NCH_BENE_DSCHRG_DT", 'YYYYMMDD')+30
where left(a."NCH_BENE_DSCHRG_DT",4)='2008'
group by a."DESYNPUF_ID", a."NCH_BENE_DSCHRG_DT";

select count(*) as admits_08,
  sum(case when readmit_dt is not null then 1 else 0 end) as readmits_08,
  1.0*sum(case when readmit_dt is not null then 1 else 0 end)/count(*) as readmit_rate
from pg_temp_3.admits08;

--Simplified simulation of HEDIS COA transition of care on 2008 data
--Just calculating denominator and numerator (only death exclusion)
--Since it's 2008, no one will be in numerator since codes did not exist yet
CREATE TEMP TABLE coa_den AS
select distinct "DESYNPUF_ID" as member_id, "BENE_BIRTH_DT", "BENE_DEATH_DT"
from raw_bene_2008
where to_date("BENE_BIRTH_DT", 'YYYYMMDD') <= '19441231' --66 years old by end of year
and "BENE_DEATH_DT" is null;

--Only checking 1st HCPCS field for the numerator codes
CREATE TEMP TABLE coa_num AS
select member_id, min(service_date) as first_service_date
from (
  select distinct "DESYNPUF_ID" as member_id,
    "HCPCS_CD_1" as HCPCS,
    to_date("CLM_FROM_DT",'YYYYMMDD') as service_date
  from raw_outpatient a
  join coa_den b on a."DESYNPUF_ID"=b.member_id
  where left(a."CLM_FROM_DT",4)='2008'
  and "HCPCS_CD_1" in ('99495','99496')
  union
  select distinct "DESYNPUF_ID" as member_id,
    "HCPCS_CD_1" as HCPCS,
    to_date("CLM_FROM_DT",'YYYYMMDD') as service_date
  from raw_carrier a
  join coa_den b on a."DESYNPUF_ID"=b.member_id
  where left(a."CLM_FROM_DT",4)='2008'
  and "HCPCS_CD_1" in ('99495','99496')
) group by member_id;

select count(a.member_id) as denominator,
  count(b.member_id) as numerator,
  1.0*count(b.member_id)/count(a.member_id) as compliance_rate
from coa_den a
left join coa_num b on a.member_id=b.member_id;

--top 10 inpatient primary Dx codes by year
CREATE TEMP TABLE top_dx AS
SELECT LEFT("CLM_FROM_DT", 4) AS yr,
         "ICD9_DGNS_CD_1"  AS dx_code1,
         sum(cast("CLM_PMT_AMT" as money)) AS total_paid
FROM raw_inpatient
WHERE "ICD9_DGNS_CD_1" <> ''
GROUP BY LEFT("CLM_FROM_DT", 4), "ICD9_DGNS_CD_1";

select yr, dx_code1, total_paid
from (select *,
    row_number() over (partition by yr order by total_paid desc) as rnk
  from top_dx
) where rnk <= 10;















