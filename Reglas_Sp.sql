-- MÓDULO 1: TRABAJADORES 
CREATE OR REPLACE PROCEDURE sp_crear_trabajador( -- Sp 1.1: agreggar un nuevo trabajador
    p_rut VARCHAR,
    p_nombre VARCHAR,
    p_telefono NUMERIC,
    p_salario NUMERIC,
    p_direccion VARCHAR,
    p_profesion VARCHAR,
    p_gerencia_id VARCHAR,
    p_obra_id VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO empleado (
        rut_dni_id, nombre_completo, telefono, salario, 
        direccion_trabajo, profesion, n_gerencia_id, codigo_obra_actual
    ) VALUES (
        p_rut, p_nombre, p_telefono, p_salario, 
        p_direccion, p_profesion, p_gerencia_id, NULLIF(p_obra_id, '')
    ); -- registramos el trabajador, con su informacion en la tabla y que si no tiene obra asignada quede en NULL
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Error: Ya existe un trabajador registrado con el RUT %.', p_rut;
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Error: La gerencia o la obra indicada no existe.';
END; -- aca los errores, si ya existe el rut entonces no se puede agregar, y si la obra no existe no se puede agregar a esa
$$;


CREATE OR REPLACE PROCEDURE sp_editar_trabajador( -- Sp 1.2: editamos los datos de los trabajadores
    p_rut VARCHAR,
    p_nombre VARCHAR,
    p_telefono NUMERIC,
    p_salario NUMERIC,
    p_profesion VARCHAR,
    p_obra_id VARCHAR 
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM empleado WHERE rut_dni_id = p_rut) THEN
        RAISE EXCEPTION 'El trabajador con RUT % no existe.', p_rut; -- obviamente si no existe el rut, no se puede editar
    END IF;

    UPDATE empleado
    SET nombre_completo = p_nombre,
        telefono = p_telefono,
        salario = p_salario,
        profesion = p_profesion,
        codigo_obra_actual = NULLIF(p_obra_id, '')
    WHERE rut_dni_id = p_rut;
END;  -- generamos el update de los datos del trabajador, si no tiene obra entonces queda en NULL 
$$;

CREATE OR REPLACE PROCEDURE sp_eliminar_trabajador( -- SP 1.3: Eliminamos al trabajdor
    p_rut VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM obra WHERE rut_dni_id = p_rut AND estado < 100) THEN
        RAISE EXCEPTION 'No se puede eliminar: El trabajador es Supervisor de una obra aún en curso.';
    END IF; -- condicion de que si el trabajador es supervisor no puede ser eliminado

    DELETE FROM empleado WHERE rut_dni_id = p_rut;
END;
$$;


-- MÓDULO 2: MAQUINARIA

CREATE OR REPLACE PROCEDURE sp_crear_maquinaria( -- SP 2.1: Registrar nueva maquinaria 
    p_codigo VARCHAR,
    p_modelo VARCHAR,
    p_marca VARCHAR,
    p_anio INT,
    p_costo_hora NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO maquinaria (codigo_maquinaria_id, modelo, marca, anio_fabricacion, costo_hora)
    VALUES (p_codigo, p_modelo, p_marca, p_anio, p_costo_hora); -- informacion de la nueva maquinaria 
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Error: Ya existe una maquinaria con el código %.', p_codigo;
END; -- comprobamos si no existe esa maquinaria dentro de las tablas
$$;

CREATE OR REPLACE PROCEDURE sp_asignar_maquinaria_obra( -- SP 2.2: Aca asignamos las maquinarias a las obras o las programamos
    p_codigo_maq VARCHAR,
    p_codigo_obra VARCHAR,
    p_fecha_inicio DATE,
    p_fecha_termino DATE,
    p_hora_inicio TIME,
    p_estado_asignacion VARCHAR 
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO asigna (
        fecha_inicio_uso, fecha_termino_uso, hora_inicio, 
        estado_asignacion, codigo_obra_id, codigo_maquinaria_id
    ) VALUES (
        p_fecha_inicio, p_fecha_termino, p_hora_inicio, 
        p_estado_asignacion, p_codigo_obra, p_codigo_maq
    );
END; -- debido a los trigger verificamos automaticamente que no choquen y que actualicen las fechas
$$;
 
CREATE OR REPLACE PROCEDURE sp_liberar_maquinaria( -- SP 2.3: aca dejamos libres a las maquinarias si terminaron una obra, osea en activa
    p_codigo_maq VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE asigna
    SET estado_asignacion = 'Finalizada',
        fecha_termino_uso = CURRENT_DATE
    WHERE codigo_maquinaria_id = p_codigo_maq 
      AND estado_asignacion = 'Activa';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La maquinaria % no tiene una obra activa en este momento.', p_codigo_maq;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_eliminar_maquinaria( -- SP 2.4: Eliminammos una maquinaria
    p_codigo_maq VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM maquinaria WHERE codigo_maquinaria_id = p_codigo_maq AND estado_actual = 'En Obra') THEN
        RAISE EXCEPTION 'No se puede eliminar: La maquinaria % se encuentra trabajando en una obra.', p_codigo_maq;
    END IF; -- con la condicion de que si la maquinaria esta en obra no se puede eliminar

    DELETE FROM maquinaria WHERE codigo_maquinaria_id = p_codigo_maq;
END;
$$;


-- MÓDULO 3: GANANCIAS, FACTURAS Y PAGOS (FINANZAS)

CREATE OR REPLACE PROCEDURE sp_registrar_pago( -- SP 3.1: Registrar nueva factura de cliente
    p_num_pago VARCHAR,
    p_monto NUMERIC,
    p_fecha DATE,
    p_estado VARCHAR, 
    p_codigo_obra VARCHAR,
    p_rut_cliente VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cliente_obra VARCHAR(25);
    v_presupuesto NUMERIC(12);
    v_total_acumulado NUMERIC(12);
BEGIN
    SELECT rut_cliente_id, presupuesto_total 
    INTO v_cliente_obra, v_presupuesto
    FROM obra
    WHERE codigo_obra_id = p_codigo_obra;

    IF v_cliente_obra IS NULL THEN
        RAISE EXCEPTION 'Error Financiero: La obra % no existe.', p_codigo_obra;
    END IF; -- validamos si la obra existe, si no existe no se puede registrar el pago

    IF v_cliente_obra <> p_rut_cliente THEN
        RAISE EXCEPTION 'Error de Trazabilidad: La obra % pertenece al cliente %, no a %.', 
            p_codigo_obra, v_cliente_obra, p_rut_cliente;
    END IF; -- validamos si la obra pertenece al cliente, si no pertenece no se puede registrar el pago

    -- Validamos que el pago no supere el presupuesto total de la obra (si no está Anulado)
    IF p_estado <> 'Anulado' THEN
        SELECT COALESCE(SUM(monto), 0) INTO v_total_acumulado
        FROM pago
        WHERE codigo_obra_id = p_codigo_obra
          AND estado IN ('Pagado', 'Pendiente');

        IF (v_total_acumulado + p_monto) > v_presupuesto THEN
            RAISE EXCEPTION 'Tope Excedido: La obra vale $% y ya tiene $% facturados. El saldo disponible es $%.',
                v_presupuesto, v_total_acumulado, (v_presupuesto - v_total_acumulado);
        END IF;
    END IF; -- si la suma pasa el presupuesto, bloquea la transacción y muestra cuánto saldo queda

    INSERT INTO pago (num_pago_id, monto, fecha, estado, codigo_obra_id, rut_cliente_id)
    VALUES (p_num_pago, p_monto, p_fecha, p_estado, p_codigo_obra, p_rut_cliente); -- gracias al trigger se guarda el nombre del cliente automaticamente
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Error: El número de factura/pago % ya está registrado.', p_num_pago;
END; -- si ya existe el numero del pago no se registra nada
$$;

CREATE OR REPLACE PROCEDURE sp_actualizar_estado_pago( -- SP 3.2: Actualizamos el estado de la factura
    p_num_pago VARCHAR,
    p_nuevo_estado VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE pago
    SET estado = p_nuevo_estado
    WHERE num_pago_id = p_num_pago;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró la factura/pago %.', p_num_pago;
    END IF; -- si no se encuentra el numero de pago no se realiza nada
END;
$$;

CREATE OR REPLACE PROCEDURE sp_eliminar_pago( -- SP 3.3: Eliminamos factura
    p_num_pago VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM pago WHERE num_pago_id = p_num_pago;
END;
$$;