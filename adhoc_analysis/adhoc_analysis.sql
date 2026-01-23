-- =========================================================
-- SQL-проект: Анализ данных строительной компании
-- Формат: бизнес-запрос → SQL-решение
-- Цель: ответить на ключевые вопросы бизнеса с помощью SQL
-- =========================================================

SET search_path TO stroy;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №1
-- Руководству необходимо оценить количество новых проектов,
-- подписанных в 2023 году, чтобы понять уровень деловой
-- активности компании за год.
--
-- Решение:
-- Получаем общее количество проектов, дата подписания
-- которых приходится на 2023 год.
-- =========================================================
SELECT
	COUNT(project_id) as signed_in_2023
FROM
	project
WHERE 
	EXTRACT(YEAR FROM sign_date) = 2023;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №2
-- HR-отдел анализирует возрастную структуру сотрудников,
-- нанятых в 2022 году. Необходимо определить суммарный
-- возраст этих сотрудников.
--
-- Решение:
-- Рассчитываем суммарный возраст сотрудников,
-- используя функцию AGE.
-- =========================================================
SELECT 
	SUM(AGE(p.birthdate)) AS sum_age
FROM 
	employee e
	JOIN person p ON p.person_id = e.person_id
WHERE 
	EXTRACT(YEAR FROM hire_date) = 2022;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №3
-- HR-службе необходимо найти сотрудника:
--  • с фамилией, начинающейся на букву «М»
--  • фамилия состоит из 8 букв
--  • сотрудник работает в компании дольше остальных
-- Если таких сотрудников несколько, необходимо выбрать
-- одного случайным образом.
--
-- Решение:
-- Фильтруем сотрудников по фамилии, сортируем по дате найма
-- и выбираем одного случайного сотрудника среди самых
-- "долгоживущих".
-- =========================================================
SELECT 
	p.first_name||' '||p.last_name AS name,
	e.hire_date
FROM 
	employee e
	JOIN person p ON p.person_id = e.person_id
WHERE 
	p.last_name ILIKE 'м_______' 
ORDER BY 
	e.hire_date,
	RANDOM()
LIMIT 1


-- =========================================================
-- БИЗНЕС-ЗАПРОС №4
-- HR-отдел анализирует возраст сотрудников, которые:
--  • уже уволены
--  • не задействованы ни в одном проекте
-- Необходимо получить средний возраст таких сотрудников.
-- Если данных нет — вернуть 0.
--
-- Решение:
-- Рассчитываем средний возраст и заменяем NULL на 0.
-- =========================================================
SELECT 
    COALESCE(AVG(EXTRACT(YEAR FROM AGE(p.birthdate))), 0) AS avg_age
FROM 
    employee e
    JOIN person p ON p.person_id = e.person_id
WHERE 
    e.dismissal_date IS NOT NULL  -- Уволенные сотрудники
    AND e.employee_id NOT IN (
        -- Все сотрудники, задействованные в проектах
        SELECT project_manager_id FROM project
        UNION ALL
        SELECT UNNEST(employees_id) FROM project
    );


-- =========================================================
-- БИЗНЕС-ЗАПРОС №5
-- Финансовый отдел хочет определить сумму фактически
-- полученных платежей от контрагентов, расположенных
-- в городе Жуковский (Россия).
--
-- Решение:
-- Суммируем только фактические платежи по заданной
-- географической локации.
-- =========================================================		
SELECT 
	SUM(pp.amount) AS zhuk_total_payments
FROM 
	project_payment pp
	JOIN project USING(project_id)
	JOIN customer c USING(customer_id)
	JOIN address a USING(address_id)
	JOIN city ct USING(city_id)
	JOIN country cntr USING(country_id)
WHERE 
	cntr.country_name = 'Россия' AND 
	ct.city_name = 'Жуковский' AND 
	pp.fact_transaction_timestamp IS NOT NULL;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №6
-- Руководство рассматривает систему мотивации, согласно
-- которой руководители проектов получают бонус в размере
-- 1% от стоимости завершённых проектов.
-- Необходимо определить руководителя (или руководителей),
-- получивших максимальный бонус.
--
-- Решение:
-- Считаем бонусы, ранжируем их и выводим максимальные значения.
-- =========================================================
WITH manager_bonus AS (
    SELECT
        p.project_manager_id,
        SUM(p.project_cost) * 0.01 AS bonus,
        DENSE_RANK() OVER (ORDER BY SUM(p.project_cost) * 0.01 DESC) AS rank
    FROM 
        project p
    WHERE 
        p.status = 'Завершен'
    GROUP BY 
        p.project_manager_id
)
SELECT
    mb.project_manager_id,
    p.first_name || ' ' || p.last_name AS full_fio,
    mb.bonus
FROM 
    manager_bonus mb
    JOIN employee e ON e.employee_id = mb.project_manager_id
    JOIN person p ON p.person_id = e.person_id
WHERE mb.rank = 1;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №7
-- Финансовый отдел анализирует планируемые авансовые платежи.
-- Необходимо определить даты, начиная с которых накопительная
-- сумма авансовых платежей по месяцам превышает 30 000 000.
--
-- Решение:
-- Рассчитываем накопительный итог внутри каждого месяца
-- и выбираем первую дату превышения порога.
-- =========================================================
WITH monthly_cumulative AS (
	--считаем накопительный итог авансовых платежей по месяцам
    SELECT
    	DISTINCT project_payment_id,
        plan_payment_date,
        amount,
        DATE_TRUNC('month', plan_payment_date) AS month,
        SUM(amount) OVER (
            PARTITION BY DATE_TRUNC('month', plan_payment_date) 
            ORDER BY plan_payment_date
        ) AS cumulative_sum
    FROM 
    	project_payment
    WHERE 
    	payment_type = 'Авансовый'
)
SELECT
	--выбираем накопления>30млн, делаем агрегацию по месяцам и выбираем первую дату
    MIN(plan_payment_date) AS first_exceed_date
FROM 
	monthly_cumulative
WHERE 
	cumulative_sum > 30000000
GROUP BY 
	month
ORDER BY 
	month;


-- =========================================================
-- БИЗНЕС-ЗАПРОС №8
-- Руководству необходимо рассчитать общий фонд оплаты труда
-- сотрудников подразделения с id = 17, включая все дочерние
-- подразделения.
--
-- Решение:
-- Используем рекурсивный запрос для получения иерархии
-- подразделений и суммируем фактические оклады.
-- =========================================================
WITH RECURSIVE recursive_salary_calc AS (
    --Стартовая часть
    SELECT 
        unit_id,
        parent_id,
        unit_name
    FROM company_structure
    WHERE unit_id = 17
    
    UNION 
    
    --Рекурсивная часть
    SELECT 
        s.unit_id,
        s.parent_id,
        s.unit_name
    FROM company_structure s
    INNER JOIN recursive_salary_calc rec ON s.parent_id = rec.unit_id
    WHERE s.unit_id != rec.unit_id 
)
SELECT SUM(ep.salary*ep.rate)
FROM 
	employee_position ep
	JOIN position p ON p.position_id = ep.position_id
WHERE 
	p.unit_id IN (
    	SELECT unit_id FROM recursive_salary_calc
	);


-- =========================================================
-- БИЗНЕС-ЗАПРОС №9
-- Финансовый отдел анализирует фактические платежи по проектам.
-- Требуется:
--  • пронумеровать платежи по годам
--  • выбрать каждый 5-й платёж
--  • рассчитать скользящее среднее платежей
--  • сравнить его с суммой стоимости проектов по годам
--  • определить годы, где стоимость проектов ниже
--    суммы скользящих средних значений
--
-- Решение:
-- Используем оконные функции, CTE и агрегирование.
-- =========================================================
WITH fact_payments AS (
    -- Фактические платежи (где fact_transaction_timestamp не NULL)
    SELECT *
    FROM project_payment
    WHERE fact_transaction_timestamp IS NOT NULL
),
numbered_payments AS (
    -- Нумерация фактических платежей по годам
    SELECT
        *,
        EXTRACT(YEAR FROM fact_transaction_timestamp) AS year,
        ROW_NUMBER() OVER (
            PARTITION BY DATE_TRUNC('year', fact_transaction_timestamp) 
            ORDER BY fact_transaction_timestamp
        ) AS rn
    FROM fact_payments
),
every_5th AS (
    -- Платежи с номером, кратным 5
    SELECT *
    FROM numbered_payments
    WHERE rn % 5 = 0
),
with_moving_avg AS (
    -- Скользящее среднее с исправленным окном
    SELECT
        *,
        AVG(amount) OVER (
            ORDER BY fact_transaction_timestamp
            ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING
        ) AS moving_avg
    FROM every_5th
),
total_moving_avg AS (
    -- Общая сумма скользящих средних
    SELECT SUM(moving_avg) AS total_avg
    FROM with_moving_avg
),
project_costs AS (
    -- Сумма стоимости проектов по годам
    SELECT
        EXTRACT(YEAR FROM sign_date) AS year,
        SUM(project_cost) AS total_cost
    FROM project
    GROUP BY EXTRACT(YEAR FROM sign_date)
)
-- Финальный результат
SELECT
    pc.year,
    pc.total_cost
FROM 
	project_costs pc
CROSS JOIN 
	total_moving_avg tma
WHERE 
	pc.total_cost < tma.total_avg;    
    
	
-- =========================================================
-- БИЗНЕС-ЗАПРОС №10
-- Необходимо сформировать единый отчёт по проектам,
-- содержащий:
--  • данные о последнем фактическом платеже
--  • ФИО руководителей проектов
--  • названия контрагентов
--  • перечень типов выполняемых работ
-- Отчёт должен храниться в виде материализованного
-- представления для быстрого доступа.
--
-- Решение:
-- Создаём материализованное представление.
-- =========================================================
CREATE MATERIALIZED VIEW task_10 AS
WITH last_payments AS (
    --Находим последний платеж для каждого проекта
    SELECT DISTINCT ON (p.project_id)
        p.project_id,
        p.project_name,
        p.project_manager_id,
        p.customer_id,
        pp.fact_transaction_timestamp::date AS fact_transaction_date,
        pp.amount
    FROM 
    	project p
    	JOIN project_payment pp ON p.project_id = pp.project_id
    WHERE 
    	pp.fact_transaction_timestamp IS NOT NULL
    ORDER BY 
    	p.project_id, pp.fact_transaction_timestamp DESC
),
new_customer_name AS (
    SELECT 
        c.customer_id,
        c.customer_name,
        --формируем строку в виде названия типов работ по каждому контрагенту
        STRING_AGG(tw.type_of_work_name, '|') AS string_type_of_work
    FROM 
    	customer c
    	JOIN customer_type_of_work ctw ON c.customer_id = ctw.customer_id
    	JOIN type_of_work tw ON ctw.type_of_work_id = tw.type_of_work_id
    GROUP BY 
    	c.customer_id, c.customer_name
)
SELECT 
    lp.project_id,
    lp.project_name,
    lp.fact_transaction_date,
    lp.amount,
    p.first_name || ' ' || p.last_name AS fio_manager,
    ncn.customer_name,
    ncn.string_type_of_work
FROM 
	last_payments lp
	JOIN employee e ON e.employee_id = lp.project_manager_id
	JOIN person p ON p.person_id = e.person_id
	JOIN new_customer_name ncn ON ncn.customer_id = lp.customer_id
ORDER BY 
	lp.project_id;



