SELECT count(1)
FROM czechia_payroll AS cp 
WHERE value IS NULL;

CREATE OR REPLACE TABLE t_jaroslav_safranek_czechia_payroll_final AS
SELECT 
	avg(cp.value) AS payroll_value,
	cp.payroll_year, 
	cpib.name AS industry_branch_name
FROM czechia_payroll AS cp 
LEFT JOIN czechia_payroll_industry_branch AS cpib 
	ON cp.industry_branch_code = cpib.code
WHERE cp.value IS NOT NULL AND cp.value_type_code = 5958
GROUP BY payroll_year, industry_branch_code ; 

CREATE OR REPLACE TABLE t_jaroslav_safranek_czechia_price_final AS
SELECT 
	avg(cp.value) AS price_value,
	YEAR(cp.date_from) AS price_year,  
	cpc.name AS category_name, 
	cpc.price_value AS category_price_value, 
	cpc.price_unit AS category_price_unit
FROM czechia_price AS cp 
JOIN czechia_price_category AS cpc 
	ON cp.category_code = cpc.code 
GROUP BY category_name, price_year;

CREATE OR REPLACE VIEW v_jaroslav_safranek_czechia_employees_per_branch AS 
SELECT 
	cpib.name, 
	avg(cp.value) * 1000 AS number_of_employee 
FROM czechia_payroll AS cp
JOIN czechia_payroll_industry_branch AS cpib 
	ON cp.industry_branch_code = cpib.code 
WHERE cp.value_type_code = 316 AND cp.value IS NOT null
GROUP BY cpib.name ;

CREATE OR REPLACE TABLE t_jaroslav_safranek_project_SQL_primary_final AS
SELECT payroll_table.*, price_table.*, vjscepb.number_of_employee 
FROM t_jaroslav_safranek_czechia_payroll_final AS payroll_table
JOIN t_jaroslav_safranek_czechia_price_final AS price_table 
	ON payroll_table.payroll_year = price_table.price_year 
JOIN v_jaroslav_safranek_czechia_employees_per_branch AS vjscepb 
	ON payroll_table.industry_branch_name = vjscepb.name ;

CREATE OR REPLACE TABLE t_jaroslav_safranek_project_SQL_secondary_final AS 
SELECT c.country, c.currency_code, e.`year`, e.GDP, e.population, e.gini, round(e.GDP/e.population) AS GDP_per_pesron 
FROM countries AS c 
JOIN economies AS e 
	ON c.country = e.country 
WHERE e.GDP IS NOT NULL;

SELECT *
FROM t_jaroslav_safranek_project_sql_secondary_final AS tjspssf ;

-- Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?
CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_1_part_1 as
SELECT 
	a.industry_branch_name, 
	a.payroll_year AS base_year, 
	b.payroll_year AS next_year, 
	round((b.payroll_value - a.payroll_value)) AS annual_growth
FROM (
	SELECT payroll_value, industry_branch_name, payroll_year 
	FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf 
	WHERE industry_branch_name IS NOT NULL) AS a
JOIN (
	SELECT *
	FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf2
	WHERE industry_branch_name IS NOT NULL
	) AS b
	ON a.payroll_year + 1 = b.payroll_year AND a.industry_branch_name = b.industry_branch_name 
GROUP BY a.payroll_year, a.industry_branch_name 
ORDER BY annual_growth;

CREATE OR REPLACE VIEW v_jaroslav_safranek_annual_growth as
SELECT 
	a.payroll_year AS base_year, 
	b.payroll_year AS next_year,
	avg(b.payroll_value) - avg(a.payroll_value) AS annual_growth
FROM (
	SELECT payroll_value, industry_branch_name, payroll_year 
	FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf 
	WHERE industry_branch_name IS NOT NULL) AS a
JOIN (
	SELECT *
	FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf2
	WHERE industry_branch_name IS NOT NULL
	) AS b
	ON a.payroll_year + 1 = b.payroll_year AND a.industry_branch_name = b.industry_branch_name
GROUP BY a.payroll_year
ORDER BY annual_growth;

-- Vážený průměr mezd
CREATE OR REPLACE VIEW v_jaroslav_safranek_payroll_sum AS 
SELECT 
	industry_branch_name, payroll_value, 
	payroll_year, 
	number_of_employee,
	number_of_employee * payroll_value AS payroll_per_branch
FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf 
GROUP BY payroll_year, industry_branch_name;

CREATE OR REPLACE VIEW v_jaroslav_safranek_weighted_average as
SELECT 
	vjsps.payroll_year AS base_year,
	vjsps2.payroll_year AS next_year,
	sum(vjsps.payroll_per_branch) / sum(vjsps2.number_of_employee) AS weighted_payroll_average, 
	sum(vjsps2.payroll_per_branch)/sum(vjsps2.number_of_employee) - sum(vjsps.payroll_per_branch)/sum(vjsps.number_of_employee) AS annual_growth 
FROM v_jaroslav_safranek_payroll_sum AS vjsps 
JOIN v_jaroslav_safranek_payroll_sum AS vjsps2 
	ON vjsps.payroll_year + 1 = vjsps2.payroll_year 
GROUP BY vjsps.payroll_year
ORDER BY annual_growth;

CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_1_part_2 AS 
SELECT 
	vjsag.base_year, 
	vjsag.next_year, 
	round(vjsag.annual_growth), 
	round(vjswa.annual_growth) AS weighted_annual_growth 
FROM v_jaroslav_safranek_annual_growth AS vjsag 
JOIN v_jaroslav_safranek_weighted_average AS vjswa 
	ON vjsag.base_year = vjswa.base_year;
	
-- Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?
CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_2 AS 
SELECT 
	tjspspf.price_year, 
	tjspspf.category_name, 
	tjspspf.category_price_value, 
	tjspspf.category_price_unit,
	round(avg(tjspspf.payroll_value) / tjspspf.price_value) AS  amount_to_buy,
	round((sum(vjsps.payroll_per_branch) / sum(vjsps.number_of_employee))/ tjspspf.price_value) AS weigthed_amount_to_buy
FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf
JOIN v_jaroslav_safranek_payroll_sum AS vjsps 
	ON tjspspf.price_year = vjsps.payroll_year 
WHERE (tjspspf.category_name LIKE '%mléko%' OR tjspspf.category_name LIKE '%chléb%') AND tjspspf.price_year IN (2006, 2018)
GROUP BY tjspspf.price_year, tjspspf.category_name ;

-- Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?
CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_3 AS 
SELECT 
	tjspspf.category_name, 
	round(avg((tjspspf2.price_value - tjspspf.price_value) / tjspspf.price_value * 100)) AS annual_price_growth
FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf
JOIN t_jaroslav_safranek_project_sql_primary_final AS tjspspf2 
	ON tjspspf.price_year + 1 = tjspspf2.price_year AND tjspspf.category_name = tjspspf2.category_name
GROUP BY tjspspf.category_name
ORDER BY annual_price_growth;

-- Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)?
CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_4 AS
SELECT 
	tjspspf.payroll_year AS base_year, 
	tjspspf2.payroll_year AS next_year, 
	round((avg(tjspspf2.payroll_value) - avg(tjspspf.payroll_value)) / avg(tjspspf.payroll_value) * 100) AS annual_payroll_growth,
	round((avg(tjspspf2.price_value)  - avg(tjspspf.price_value)) / avg(tjspspf.price_value)  * 100) AS annual_price_growth,
	round((avg(tjspspf2.payroll_value) - avg(tjspspf.payroll_value)) / avg(tjspspf.payroll_value) * 100) - round((avg(tjspspf2.price_value)  - avg(tjspspf.price_value)) / avg(tjspspf.price_value)  * 100) AS difference
FROM t_jaroslav_safranek_project_sql_primary_final AS tjspspf 
JOIN t_jaroslav_safranek_project_sql_primary_final AS tjspspf2 
	ON tjspspf.payroll_year + 1 = tjspspf2.payroll_year 
		AND tjspspf.industry_branch_name = tjspspf2.industry_branch_name 
		AND tjspspf.category_name = tjspspf2.category_name
GROUP BY tjspspf.payroll_year;

-- Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?
CREATE OR REPLACE VIEW v_jaroslav_safranek_economic_czechia AS
SELECT 
	tjspssf.`year`, 
	avg(tjspssf.GDP) AS gdp, 
	avg(tjspspf.payroll_value) AS payroll_value, 
	avg(tjspspf.price_value) AS price_value 
FROM t_jaroslav_safranek_project_sql_secondary_final AS tjspssf
JOIN t_jaroslav_safranek_project_sql_primary_final AS tjspspf
	ON tjspssf.`year` = tjspspf.payroll_year 
WHERE tjspssf.country = "Czech republic"
GROUP BY `year` ;

CREATE OR REPLACE VIEW v_jaroslav_safranek_answer_5 AS
SELECT 
	vjsec.`year` AS base_year,
	vjsec2.`year` AS next_year,
	round((vjsec2.gdp - vjsec.gdp) / vjsec.gdp *100) AS annual_gdp_growth,
	round((vjsec2.payroll_value - vjsec.payroll_value)/vjsec.payroll_value *100) AS annual_payroll_growth,
	round((vjsec2.price_value - vjsec.price_value)/vjsec.price_value *100) AS annual_price_growth
FROM v_jaroslav_safranek_economic_czechia AS vjsec
JOIN v_jaroslav_safranek_economic_czechia AS vjsec2 
	ON vjsec.`year` + 1 = vjsec2.`year` ;

-- Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?
SELECT *
FROM v_jaroslav_safranek_answer_1_part_1 AS vjsap;

SELECT * 
FROM v_jaroslav_safranek_answer_1_part_2 AS vjsap;

-- Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?
SELECT *
FROM v_jaroslav_safranek_answer_2 AS vjsa ;

-- Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?
SELECT *
FROM v_jaroslav_safranek_answer_3 AS vjsa ;

-- Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)?
SELECT *
FROM v_jaroslav_safranek_answer_4 AS vjsa ;

-- Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo násdujícím roce výraznějším růstem?
SELECT *
FROM v_jaroslav_safranek_answer_5 AS vjsa ;