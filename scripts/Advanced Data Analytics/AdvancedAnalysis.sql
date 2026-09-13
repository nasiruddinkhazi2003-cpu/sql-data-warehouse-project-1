--==================================
-- Change Over Time
--==================================

-- Analyze Sales Performance Over Time
SELECT 
	YEAR(order_date) AS order_year,
	MONTH(order_date) AS order_month,
	SUM(sales) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date),MONTH(order_date)
ORDER BY YEAR(order_date) ASC, MONTH(order_date) ASC

--OR

SELECT 
	DATETRUNC(month,order_date) AS order_date,
	SUM(sales) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(month,order_date) 
ORDER BY DATETRUNC(month,order_date) ASC

--OR
SELECT 
	FORMAT(order_date, 'yyyy-MMM') AS order_date,
	SUM(sales) AS total_sales,
	COUNT(DISTINCT customer_key) AS total_customers,
	SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM') ASC

--==================================
-- Cumulative Analysis
--==================================

-- Calculate the total sales per month and
-- the running total of sales over time
SELECT
order_date,
total_sales,
SUM(total_sales) OVER(ORDER BY order_date) AS running_total_sales,
AVG(average_price) OVER(ORDER BY order_date) AS moving_average_price
FROM
(SELECT
	DATETRUNC(year,order_date) AS order_date,
	SUM(sales) AS total_sales,
	AVG(price) AS average_price
FROM gold.fact_sales
WHERE DATETRUNC(year,order_date) IS NOT NULL
GROUP BY DATETRUNC(year,order_date)
)t

--==================================
-- Performance Analysis
--==================================

/* Analyze the yearly performance of products by 
   comparing each products sales to both its average
   sales performance and the previous years sales. */

WITH yearly_product_sales AS (
SELECT 
	YEAR(f.order_date) AS order_year,
	p.product_name,
	SUM(f.sales) AS current_sales
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_products AS p
ON f.product_key = p.product_key
WHERE  f.order_date IS NOT NULL
GROUP BY YEAR(f.order_date), p.product_name
)

SELECT
	order_year,
	product_name,
	current_sales,
	AVG(current_sales) OVER(PARTITION BY product_name) AS average_sales,
	current_sales - AVG(current_sales) OVER(PARTITION BY product_name) AS diff_average,
	CASE WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) > 0 THEN 'Above Average'
		 WHEN current_sales - AVG(current_sales) OVER(PARTITION BY product_name) < 0 THEN 'Below Average'
		 ELSE 'Average'
	END AS average_change,

	-- Year-Over-Year Analysis
	LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS previousyear_sales,
	current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS diff_py,
	CASE WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
		 WHEN current_sales - LAG(current_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
		 ELSE 'No Change'
	END AS previousyear_change
FROM yearly_product_sales
ORDER BY product_name, order_year


--==================================
-- Part-to-Whole Analysis
--==================================

-- Which categories contribute the most to overall sales?
WITH category_sales AS(
SELECT
category,
SUM(sales) AS total_sales
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_products AS p
ON p.product_key = f.product_key
GROUP BY category
)
SELECT 
	category,
	total_sales,
	SUM(total_sales) OVER() AS overall_sales,
	CONCAT(ROUND((CAST(total_sales AS FLOAT)/SUM(total_sales) OVER()) * 100,2), '%' ) AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC


--==================================
-- Data Segmentation
--==================================

-- Segment products into cost ranges and 
-- count how many products fall into each segment

WITH product_segments AS(
SELECT
	product_key,
	product_name,
	cost,
	CASE WHEN cost < 100 THEN 'Below 100'
		 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
		 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
		 ELSE 'Above 1000'
	END AS cost_range
FROM gold.dim_products 
) 
SELECT 
	cost_range,
	COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC


/* Group customers into three segments based on their spending behavior:
	- VIP: atleast 12 months of history and spending more than 5000.
	- Regular: atleast 12 months of history but spending 5000 or less.
	- New: lifespan less than 12 months 
 And find the total number of customers by each group.
*/
WITH customer_spending AS (
SELECT
	c.customer_key,
	SUM(f.sales) AS total_spending,
	MIN(f.order_date) AS first_order,
	MAX(f.order_date) AS last_order,
	DATEDIFF(month,MIN(f.order_date),MAX(f.order_date)) AS lifespan
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_customers AS c
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)

SELECT 
	customer_segment,
	COUNT(customer_key)  AS total_customers
FROM(
	SELECT
		customer_key,
		CASE WHEN lifespan >= 12 and total_spending > 5000 THEN 'VIP'
			 WHEN lifespan >= 12 and total_spending <= 5000 THEN 'Regular'
			 ELSE 'New'
		END AS customer_segment
	FROM customer_spending
	)t
GROUP BY customer_segment
ORDER BY total_customers DESC

	
--==================================
-- Reporting
--==================================


/*
==================================================================
Customer Report
==================================================================
Purpose:
	- This report consolidates key customer metrics and behaviors 

Highlights:
	1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer-level metrics:
		- total orders 
		- total sales
		- total quantity purchased 
		- total products 
		- lifespan (in months)
	4. Calculates valuable KPIs:
		- recency (months since last order)
		- average order value
		- average monthly spend
====================================================================
*/
CREATE VIEW gold.report_customers AS
WITH base_query AS (
/*----------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
------------------------------------------------------------------*/
SELECT
	f.order_number,
	f.product_key,
	f.order_date,
	f.sales,
	f.quantity,
	c.customer_key,
	c.customer_number,
	CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
	DATEDIFF(year, c.birthdate, GETDATE()) AS age
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_customers AS c
ON c.customer_key = f.customer_key
WHERE order_date IS NOT NULL
)
, customer_aggregation AS(
/*--------------------------------------------------------------------
2) Customer Aggregations: Summarizes key metrics at the customer level
----------------------------------------------------------------------*/
SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
	COUNT(DISTINCT order_number) AS total_orders,
	SUM(sales) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	DATEDIFF(month,MIN(order_date),MAX(order_date)) AS lifespan
FROM base_query
GROUP BY 
	customer_key,
	customer_number,
	customer_name,
	age
)

SELECT
	customer_key,
	customer_number,
	customer_name,
	age,
	CASE WHEN age < 20 THEN 'Under 20'
		 WHEN age BETWEEN 20 AND 29 THEN '20-29'
		 WHEN age BETWEEN 30 AND 39 THEN '30-39'
		 WHEN age BETWEEN 40 AND 49 THEN '40-49'
		 ELSE '50 and above'
	END AS age_group,
	CASE WHEN lifespan >= 12 and total_sales > 5000 THEN 'VIP'
			 WHEN lifespan >= 12 and total_sales <= 5000 THEN 'Regular'
			 ELSE 'New'
	END AS customer_segment,
	last_order_date,
	DATEDIFF(month, last_order_date, GETDATE()) AS recency,
	total_orders,
	total_sales,
	total_quantity,
	total_products,
	lifespan,
	-- Compute average order value (AVO)
	CASE WHEN total_sales = 0 THEN 0
		 ELSE total_sales / total_orders
	END AS average_order_value,

	-- Compute average monthly spend
	CASE WHEN lifespan = 0 THEN total_sales
		 ELSE total_sales / lifespan
	END AS average_monthly_spend
	FROM customer_aggregation



	--===================================
	-- Execute view gold.report_customers

	SELECT * FROM gold.report_customers
