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
AVG(average_price) OVER(ORDER BY order_date) AS running_average_price
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
