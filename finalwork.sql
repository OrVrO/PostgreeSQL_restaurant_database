create schema restaurant;

SET search_path TO restaurant;

---- �������� ������ � �������� ------

---- ���������� -----
create table if not exists positions(
	title_id serial primary key,
	title_name varchar,
	title_salary numeric,
	work_hours int -- ����� �������� ������� ��� ���������
);

create table if not exists employees(
	employee_id serial primary key,
	firstname varchar,
	secondname varchar,
	middlename varchar,
	job_title int references positions -- ��������� ����������
);

create table if not exists time_sheet(
	employee_id int references employees,
	time_start timestamp, -- ����������� ������ �������� ���
	time_finish timestamp -- ����������� ��������� �������� ���
);


---- ���� ----
create table if not exists menu_level1(
	menu_l1_id serial primary key,
	menu_l1_name varchar unique);

create table if not exists meals(
	meal_id serial primary key,
	meal_name varchar unique,
	meal_cost numeric not null);

create table if not exists menu_level2(
	menu_l2_id serial primary key,
	menu_l1 int references menu_level1 (menu_l1_id),
	meal  int references meals (meal_id),
	menu_l2_name varchar);	

---- ������ ----
create table if not exists discounts(
	discount_id serial primary key,
	discount_sum numeric,
	discount_name varchar unique);

create table if not exists orders(
	order_id serial primary key,
	waiter int references employees (employee_id) not null,
	order_date timestamp default current_timestamp,
	discount int references discounts (discount_id) default 1,
	status varchar default '����� ������');

create or replace trigger trigger_add_order_check_waiter --- ����� ����� ��������� ������ �������� ��� �������������
before insert on orders for each row execute function add_order_check_waiter_func();

create or replace function add_order_check_waiter_func()
returns trigger
language plpgsql
as 
$$
declare
	employee_title varchar = (select p.title_name
							  from employees e
							  join positions p on p.title_id = e.job_title 
							  where e.employee_id = new.waiter); -- ����� ��������� ���������
begin
	if employee_title like '��������' then
		return new;
	elsif employee_title like '�������������' then
		return new;
	else
		return null;
	end if;
	return null;
end
$$

create table if not exists orders_details(
	order_id int references orders (order_id) on delete cascade on update cascade,
	meal_id int references meals (meal_id) not null,
	qty int default 1
	);

create table if not exists bills(
	bill_id serial primary key,
	order_id int references orders (order_id) unique,
	paid_amount numeric default 0,
	date_paid timestamp default current_timestamp
	);

create or replace trigger trigger_upd_order_status --- ���������� ������� ������
after insert on bills for each row execute function upd_order_status_func();

create or replace function upd_order_status_func()
returns trigger
language plpgsql
as 
$$
begin
	update orders set status = '���� ����� ��� ������' where order_id = new.order_id;
	return null;
end
$$

create or replace procedure make_bill(order_number int) -- ��������� ��� ������ ����� ��� ������ ������
language plpgsql
as 
$$
declare
	paid_sum numeric =     (select distinct sum((m.meal_cost * od.qty) - (m.meal_cost * od.qty * d.discount_sum)) over () 
							  from orders_details od 
							  join meals m on od.meal_id = m.meal_id
	                          join orders o on o.order_id = od.order_id
	                          join discounts d on d.discount_id = o.discount
	                          where od.order_id = order_number);
begin
	insert into bills(order_id, paid_amount) values (order_number, paid_sum);
end
$$

---- �������������� ������������� �������� ----
create table if not exists frauds(
	fraud_id serial primary key,
	fraud_user varchar,
	date_action timestamp default current_timestamp,
	action_text varchar
	);

create or replace trigger trigger_upd_orders_discount --- ���������� ������ � ������
before update on orders for each row execute function upd_orders_discount_func();

create or replace function upd_orders_discount_func()
returns trigger
language plpgsql
as 
$$
begin
	if old.status like '���� ����� ��� ������' then
		insert into frauds(fraud_user, action_text) values (current_user, '������� �������� �������� ����� ' || new);
		return null;
	else
		return new;
    end if;
	return null;
end
$$

----- �������� ������������� ----

create or replace view menu
as
select
	ml.menu_l1_name "�������� ����",
	ml2.menu_l2_name "���������",
	m.meal_name "�������� �����",
	m.meal_cost "���� �����"
from menu_level1 ml
join menu_level2 ml2 on ml.menu_l1_id = ml2.menu_l1 
join meals m on m.meal_id = ml2.meal
order by ml.menu_l1_name, ml2.menu_l2_name, m.meal_name;


create or replace view open_orders
as
select distinct
	o.order_id "����� ������",
	o.order_date "���� ������",
	es."���_����������" "��������",
	d.discount_sum * 100  || ' % ������ �� ����� ' || d.discount_name "������",
    m.meal_name "�����",
    od.qty "����������",
    ((m.meal_cost * od.qty) - (m.meal_cost * od.qty * d.discount_sum)) "���������"
from orders o
join orders_details od on o.order_id = od.order_id
join meals m on m.meal_id = od.meal_id
join employee_sheet es on o.waiter = es."������_�����_����������" 
join discounts d on d.discount_id = o.discount 
where o.status like '����� ������';


create or replace view close_orders
as
select distinct
	o.order_id "����� ������",
	o.order_date "���� ������",
	es."���_����������" "��������",
	sum(m.meal_cost * od.qty) over (partition by o.order_id) "����� ������",
	sum(m.meal_cost * od.qty * d.discount_sum) over (partition by o.order_id) "������",
    sum((m.meal_cost * od.qty) - (m.meal_cost * od.qty * d.discount_sum)) over (partition by o.order_id) "�������",
    (select sum(paid_amount) from bills where
    		   extract(day from current_timestamp) = extract(day from date_paid) 
			   and extract(month from current_timestamp) = extract(month from date_paid)
			   and extract(year from current_timestamp) = extract(year from date_paid)) "����� ����� ������� �� �������"
from orders o
join orders_details od on o.order_id = od.order_id
join meals m on m.meal_id = od.meal_id
join employee_sheet es on o.waiter = es."������_�����_����������" 
join discounts d on d.discount_id = o.discount 
join bills b on o.order_id = b.order_id
where o.status like '���� ����� ��� ������' 
			   and extract(day from current_timestamp) = extract(day from b.date_paid) 
			   and extract(month from current_timestamp) = extract(month from b.date_paid)
			   and extract(year from current_timestamp) = extract(year from b.date_paid);
			  
			  
create or replace view discounts_view
as
select
	d.discount_sum * 100 || ' %' "������",
	d.discount_name "�������� ������"
from discounts d
where d.discount_sum  <> 0;


create or replace view employee_sheet
as
select
	e.employee_id "������_�����_����������",
	e.secondname ||' '|| e.firstname ||' '|| e.middlename "���_����������",
	p.title_name "���������"
from
	employees e
join positions p on p.title_id = e.job_title;


create or replace view staff_rating
as
select distinct
	(select distinct 
	sum(b.paid_amount) over (partition by o.waiter)
	from bills b
	join orders o2 on o2.order_id = b.order_id
	where o2.waiter = o.waiter) "����� �������",
	e.secondname ||' '|| e.firstname ||' '|| e.middlename "���������"
from orders o
join bills b on b.order_id = o.order_id
join employees e on e.employee_id = o.waiter
order by "����� �������" desc;

create or replace view staff_fraud
as
select
	f.date_action "���� ��������",
	f.fraud_user "������������",
	f.action_text "��������"
from frauds f
order by f.date_action; 


----- ���������� ������ -----

---- ���������� ----
insert into positions(
	title_name,
	title_salary,
	work_hours
)
values 
	('��������', 100000, 8),
	('�������������', 70000, 12),
	('��������', 50000, 12),
	('�������', 25000, 4),
	('��������', 50000, 12),
	('������������', 30000, 4),
	('������', 40000, 8),
	('���������', 55000, 8),
	('������-������', 60000, 12),
	('�����', 58000, 12);

insert into employees(	
	firstname,
	secondname,
	middlename,
	job_title
)
values 
	('����', '������', '��������', 1),
	('����', '������', '��������', 2),
	('����', '������', '��������', 2),
	('�������','������','���������', 3),
	('��������','������','����������', 3),
	('�������','���������','�������������', 3),
	('�������','Ը���','�������������', 3),
	('�����','���������','�������������',4),
	('������','���������','��������', 4),
	('������','�����','����������', 5),
	('������','������','����������', 5),
	('�������','�������','���������', 6),
	('�������','��������','��������', 6),
	('�������','������','����������', 7),
	('�������','������','��������', 8),
	('������','����','��������', 9),
	('������','���������','���������', 9),
	('��������','���������','��������', 10),
	('��������','����','����������', 10);
	
insert into time_sheet(
	employee_id,
	time_start,
	time_finish
)
values 
	(1, '2022-08-17 9:00', '2022-08-17 18:00'),
	(1, '2022-08-16 8:00', '2022-08-16 17:00'),
	(1, '2022-08-15 10:00', '2022-08-15 16:00'),
	(1, '2022-08-14 9:00', '2022-08-14 18:00'),
	(1, '2022-08-13 8:00', '2022-08-13 17:00'),
	(1, '2022-08-12 10:00', '2022-08-12 16:00'),
	(1, '2022-08-11 10:00', '2022-08-11 16:00'),
	(2, '2022-08-17 9:00', '2022-08-17 21:00'),
	(2, '2022-08-16 9:00', '2022-08-16 21:10'),
	(2, '2022-08-15 9:00', '2022-08-15 21:20'),
	(2, '2022-08-14 9:00', '2022-08-14 21:00'),
	(2, '2022-08-13 9:00', '2022-08-13 21:10'),
	(2, '2022-08-12 9:00', '2022-08-12 21:20'),
	(2, '2022-08-11 9:00', '2022-08-11 21:20'),
	(3, '2022-08-24 9:00', '2022-08-24 21:00'),
	(3, '2022-08-23 9:00', '2022-08-23 21:10'),
	(3, '2022-08-22 9:00', '2022-08-22 21:20'),
	(3, '2022-08-21 9:00', '2022-08-21 21:00'),
	(3, '2022-08-20 9:00', '2022-08-20 21:10'),
	(3, '2022-08-19 9:00', '2022-08-19 21:20'),
	(3, '2022-08-18 9:00', '2022-08-18 21:20'),
	(4, '2022-08-17 9:00', '2022-08-17 21:00'),
	(4, '2022-08-16 9:00', '2022-08-16 21:10'),
	(4, '2022-08-15 9:00', '2022-08-15 21:20'),
	(4, '2022-08-14 9:00', '2022-08-14 21:00'),
	(4, '2022-08-13 9:00', '2022-08-13 21:10'),
	(4, '2022-08-12 9:00', '2022-08-12 21:20'),
	(4, '2022-08-11 9:00', '2022-08-11 21:20'),	
	(5, '2022-08-17 9:00', '2022-08-17 21:00'),
	(5, '2022-08-16 9:00', '2022-08-16 21:10'),
	(5, '2022-08-15 9:00', '2022-08-15 21:20'),
	(5, '2022-08-14 9:00', '2022-08-14 21:00'),
	(5, '2022-08-13 9:00', '2022-08-13 21:10'),
	(5, '2022-08-12 9:00', '2022-08-12 21:20'),
	(5, '2022-08-11 9:00', '2022-08-11 21:20'),
	(6, '2022-08-24 9:00', '2022-08-24 21:00'),
	(6, '2022-08-23 9:00', '2022-08-23 21:10'),
	(6, '2022-08-22 9:00', '2022-08-22 21:20'),
	(6, '2022-08-21 9:00', '2022-08-21 21:00'),
	(6, '2022-08-20 9:00', '2022-08-20 21:10'),
	(6, '2022-08-19 9:00', '2022-08-19 21:20'),
	(6, '2022-08-18 9:00', '2022-08-18 21:20'),
	(7, '2022-08-24 9:00', '2022-08-24 21:00'),
	(7, '2022-08-23 9:00', '2022-08-23 21:10'),
	(7, '2022-08-22 9:00', '2022-08-22 21:20'),
	(7, '2022-08-21 9:00', '2022-08-21 21:00'),
	(7, '2022-08-20 9:00', '2022-08-20 21:10'),
	(7, '2022-08-19 9:00', '2022-08-19 21:20'),
	(7, '2022-08-18 9:00', '2022-08-18 21:20'),
	(8, '2022-08-17 17:00', '2022-08-17 21:00'),
	(8, '2022-08-16 17:00', '2022-08-16 21:10'),
	(8, '2022-08-15 17:00', '2022-08-15 21:20'),
	(8, '2022-08-14 17:00', '2022-08-14 21:00'),
	(8, '2022-08-13 17:00', '2022-08-13 21:10'),
	(8, '2022-08-12 17:00', '2022-08-12 21:20'),
	(8, '2022-08-11 17:00', '2022-08-11 21:20'),
	(9, '2022-08-24 17:00', '2022-08-24 21:00'),
	(9, '2022-08-23 17:00', '2022-08-23 21:10'),
	(9, '2022-08-22 17:00', '2022-08-22 21:20'),
	(9, '2022-08-21 17:00', '2022-08-21 21:00'),
	(9, '2022-08-20 17:00', '2022-08-20 21:10'),
	(9, '2022-08-19 17:00', '2022-08-19 21:20'),
	(9, '2022-08-18 17:00', '2022-08-18 21:20'),
	(10, '2022-08-17 9:00', '2022-08-17 21:00'),
	(10, '2022-08-16 9:00', '2022-08-16 21:10'),
	(10, '2022-08-15 9:00', '2022-08-15 21:20'),
	(10, '2022-08-14 9:00', '2022-08-14 21:00'),
	(10, '2022-08-13 9:00', '2022-08-13 21:10'),
	(10, '2022-08-12 9:00', '2022-08-12 21:20'),
	(10, '2022-08-11 9:00', '2022-08-11 21:20'),
	(11, '2022-08-24 9:00', '2022-08-24 21:00'),
	(11, '2022-08-23 9:00', '2022-08-23 21:10'),
	(11, '2022-08-22 9:00', '2022-08-22 21:20'),
	(11, '2022-08-21 9:00', '2022-08-21 21:00'),
	(11, '2022-08-20 9:00', '2022-08-20 21:10'),
	(11, '2022-08-19 9:00', '2022-08-19 21:20'),
	(11, '2022-08-18 9:00', '2022-08-18 21:20'),
	(12, '2022-08-17 17:00', '2022-08-17 21:00'),
	(12, '2022-08-16 17:00', '2022-08-16 21:10'),
	(12, '2022-08-15 17:00', '2022-08-15 21:20'),
	(12, '2022-08-14 17:00', '2022-08-14 21:00'),
	(12, '2022-08-13 17:00', '2022-08-13 21:10'),
	(12, '2022-08-12 17:00', '2022-08-12 21:20'),
	(12, '2022-08-11 17:00', '2022-08-11 21:20'),
	(13, '2022-08-24 17:00', '2022-08-24 21:00'),
	(13, '2022-08-23 17:00', '2022-08-23 21:10'),
	(13, '2022-08-22 17:00', '2022-08-22 21:20'),
	(13, '2022-08-21 17:00', '2022-08-21 21:00'),
	(13, '2022-08-20 17:00', '2022-08-20 21:10'),
	(13, '2022-08-19 17:00', '2022-08-19 21:20'),
	(13, '2022-08-18 17:00', '2022-08-18 21:20'),
	(14, '2022-08-17 9:00', '2022-08-17 18:00'),
	(14, '2022-08-16 8:00', '2022-08-16 17:00'),
	(14, '2022-08-15 10:00', '2022-08-15 16:00'),
	(14, '2022-08-14 9:00', '2022-08-14 18:00'),
	(14, '2022-08-13 8:00', '2022-08-13 17:00'),
	(14, '2022-08-12 10:00', '2022-08-12 16:00'),
	(14, '2022-08-11 10:00', '2022-08-11 16:00'),	
	(15, '2022-08-17 9:00', '2022-08-17 18:00'),
	(15, '2022-08-16 8:00', '2022-08-16 17:00'),
	(15, '2022-08-15 10:00', '2022-08-15 16:00'),
	(15, '2022-08-14 9:00', '2022-08-14 18:00'),
	(15, '2022-08-13 8:00', '2022-08-13 17:00'),
	(15, '2022-08-12 10:00', '2022-08-12 16:00'),
	(15, '2022-08-11 10:00', '2022-08-11 16:00'),	
	(16, '2022-08-17 9:00', '2022-08-17 21:00'),
	(16, '2022-08-16 9:00', '2022-08-16 21:10'),
	(16, '2022-08-15 9:00', '2022-08-15 21:20'),
	(16, '2022-08-14 9:00', '2022-08-14 21:00'),
	(16, '2022-08-13 9:00', '2022-08-13 21:10'),
	(16, '2022-08-12 9:00', '2022-08-12 21:20'),
	(16, '2022-08-11 9:00', '2022-08-11 21:20'),
	(17, '2022-08-24 9:00', '2022-08-24 21:00'),
	(17, '2022-08-23 9:00', '2022-08-23 21:10'),
	(17, '2022-08-22 9:00', '2022-08-22 21:20'),
	(17, '2022-08-21 9:00', '2022-08-21 21:00'),
	(17, '2022-08-20 9:00', '2022-08-20 21:10'),
	(17, '2022-08-19 9:00', '2022-08-19 21:20'),
	(17, '2022-08-18 9:00', '2022-08-18 21:20'),
	(18, '2022-08-17 9:00', '2022-08-17 21:00'),
	(18, '2022-08-16 9:00', '2022-08-16 21:10'),
	(18, '2022-08-15 9:00', '2022-08-15 21:20'),
	(18, '2022-08-14 9:00', '2022-08-14 21:00'),
	(18, '2022-08-13 9:00', '2022-08-13 21:10'),
	(18, '2022-08-12 9:00', '2022-08-12 21:20'),
	(18, '2022-08-11 9:00', '2022-08-11 21:20'),
	(19, '2022-08-24 9:00', '2022-08-24 21:00'),
	(19, '2022-08-23 9:00', '2022-08-23 21:10'),
	(19, '2022-08-22 9:00', '2022-08-22 21:20'),
	(19, '2022-08-21 9:00', '2022-08-21 21:00'),
	(19, '2022-08-20 9:00', '2022-08-20 21:10'),
	(19, '2022-08-19 9:00', '2022-08-19 21:20'),
	(19, '2022-08-18 9:00', '2022-08-18 21:20');


------ ���� -----
insert into menu_level1(
	menu_l1_name
)
values 
	('��������'),
	('������-����'),
	('������ �����');
	
insert into meals(
	meal_name,
	meal_cost
)
values 
	('��� ���������', 300),
	('�������', 250),
	('����', 350),
    ('�������', 400),
    ('�����', 400),
    ('���� �������', 300),
    ('������� �� �������', 350),
    ('��������� ��������', 100),
    ('��������� ���', 150),
    ('���', 80),
    ('��������', 70),
    ('����� ������', 450),
    ('����� ���������', 400),
    ('����� ����������', 200),
    ('����� ������', 300),
    ('����� ��������', 400),
    ('����� � ���������', 250),
    ('����� � ��������', 250),
    ('����� � ������', 250),
    ('������� ��-�������', 300),
    ('����� �����', 800),
    ('������ �� ��������', 200),
    ('������ �� �������', 200),
    ('�����', 250),
    ('����', 250),
    ('�����', 250),
    ('���', 150),
    ('���', 150),
    ('������', 250),
    ('���', 250),
    ('����������� ����', 150),
    ('����', 150),
    ('���������', 150),
    ('������� �����', 300),
    ('������� �����������', 300),
    ('����� �����������', 300),
    ('����� �����', 300),
    ('����������', 300);

insert into menu_level2(
	menu_l1,
	meal,
	menu_l2_name
	)	
values 
	(1, 1, '����'),
	(1, 2, '����'),
	(1, 3, '����'),
	(1, 4, '����'),
	(1, 5, '����'),
	(1, 6, '������ �����'),
	(1, 7, '������ �����'),
	(1, 8, '������ �����'),
	(1, 9, '������ �����'),
	(1, 10, '������ �����'),
	(1, 11, '������ �����'),
	(1, 12, '������'),
	(1, 13, '������'),
	(1, 14, '������'),
	(1, 15, '������'),
	(1, 16, '������'),
	(2, 1, '����� 1'),
	(2, 6, '����� 1'),
	(2, 7, '����� 1'),
	(2, 12, '����� 1'),
	(2, 28, '����� 1'),
	(2, 2, '����� 2'),
	(2, 8, '����� 2'),
	(2, 20, '����� 2'),
	(2, 15, '����� 2'),
	(2, 27, '����� 2'),
	(2, 3, '����� 3'),
	(2, 10, '����� 3'),
	(2, 23, '����� 3'),
	(2, 13, '����� 3'),
	(2, 27, '����� 3'),
	(3, 24, '������� �������'),
	(3, 25, '������� �������'),
	(3, 26, '������� �������'),
	(3, 29, '������� �������'),
	(3, 30, '������� �������'),
	(3, 34, '����'),
	(3, 35, '����'),
	(3, 36, '����'),
	(3, 37, '����'),
	(3, 38, '����'),
	(3, 28, '�������������� �������'),
	(3, 27, '�������������� �������'),
	(3, 31, '�������������� �������'),
	(3, 32, '�������������� �������'),
	(3, 33, '�������������� �������');


------ ������ -----
insert into discounts(
	discount_sum,
	discount_name)
values
	(0, '��� ������'),
	(0.10 , '����������� ������'),
	(0.15 , '������� ������');

insert into orders(
	waiter,
	order_date,
	discount)
values
	(4, '2022-08-11 10:00', 1),
	(5, '2022-08-11 11:00', 1),
	(4, '2022-08-11 12:00', 2),
	(5, '2022-08-12 13:00', 1),
	(4, '2022-08-12 14:00', 1),
	(5, '2022-08-12 15:00', 3),
	(4, '2022-08-13 16:00', 1),
	(5, '2022-08-13 17:00', 1),
	(4, '2022-08-13 18:00', 2),
	(5, '2022-08-14 19:00', 1),
	(4, '2022-08-14 20:00', 1),
	(5, '2022-08-14 10:00', 2),
	(4, '2022-08-15 11:00', 1),
	(5, '2022-08-15 12:00', 1),
	(4, '2022-08-15 13:00', 3),
	(5, '2022-08-16 14:00', 1),
	(4, '2022-08-16 15:00', 1),
	(5, '2022-08-16 16:00', 2),
	(4, '2022-08-17 17:00', 1),
	(5, '2022-08-17 18:00', 1),
	(4, '2022-08-17 19:00', 3);


insert into orders_details(
	order_id,
	meal_id,
	qty)
values
	(1, 1, 1),
	(1, 2, 2),
	(1, 3, 3),
	(2, 4, 2),
	(2, 5, 2),
	(3, 6, 1),
	(3, 7, 1),
	(4, 8, 1),
	(4, 9, 1),
	(5, 10, 1),
	(6, 11, 1),
	(7, 12, 3),
	(7, 1, 3),
	(8, 13, 2),
	(8, 14, 1),
	(8, 15, 1),
	(9, 16, 2),
	(9, 17, 2),
	(9, 18, 2),
	(10, 19, 2),
	(10, 20, 2),
	(10, 21, 2),
	(11, 22, 5),
	(12, 23, 1),
	(12, 24, 1),
	(13, 25, 2),
	(14, 26, 2),
	(15, 27, 2),
	(16, 28, 2),
	(17, 29, 2),
	(18, 30, 2),
	(19, 31, 2),
	(19, 32, 2),
	(19, 33, 2),
	(20, 34, 2),
	(21, 35, 2),
	(21, 36, 2);



call make_bill(1);


update orders set discount = 3 where order_id = 8;
