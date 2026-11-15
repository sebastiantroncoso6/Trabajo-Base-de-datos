-- TRIGGER 1: Control de disponibilidad y desnormalización de TRABAJADORES
-- Regla: Un trabajador no puede entrar a una obra si ya está asignado a otra. Además se debe rellenar si se encuentra en alguna obra para que no choque entre obras.
CREATE OR REPLACE FUNCTION fn_validar_y_sincronizar_empleado()
RETURNS TRIGGER AS $$
DECLARE
    v_direccion_obra VARCHAR(50);
    v_tipo_obra VARCHAR(50);
BEGIN
    IF NEW.codigo_obra_actual IS NOT NULL THEN -- primero si el trabajador no tiene ninguna obra, se la asignamos, aca tenemos el primer trigger que es para la clase de trabajador 
        
        IF TG_OP = 'UPDATE' AND OLD.codigo_obra_actual IS NOT NULL 
           AND OLD.codigo_obra_actual <> NEW.codigo_obra_actual THEN
            RAISE EXCEPTION 'Conflicto Operativo: El trabajador % (%) ya se encuentra asignado a la obra %. Debe liberarlo primero.', 
                NEW.nombre_completo, NEW.rut_dni_id, OLD.codigo_obra_actual;
        END IF; -- aca la primera condicion, si al hacer el update ya tiene una obra a la misma fecha, suelta el error de que no se puede, por eso se ocupa el old is not full

        SELECT direccion, tipo_estructura INTO v_direccion_obra, v_tipo_obra
        FROM obra
        WHERE codigo_obra_id = NEW.codigo_obra_actual; -- aca buscamos los datos de la obra, osea ocupamos desnormalizacion

        NEW.obra_actual_desc := NEW.codigo_obra_actual || ' - ' || COALESCE(v_tipo_obra, 'Obra') || ' (' || v_direccion_obra || ')';
    ELSE
        NEW.obra_actual_desc := 'Disponible'; -- si esta null la obra, entonces suelta el mensaje disponible, indicando que se puede adherir a una obra
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_empleado_obra
BEFORE INSERT OR UPDATE OF codigo_obra_actual ON empleado
FOR EACH ROW
EXECUTE FUNCTION fn_validar_y_sincronizar_empleado();


-- TRIGGER 2: Control de MAQUINARIA / EXCAVADORAS
-- Regla: Evita que una máquina se programe en dos obras en fechas superpuestas.
CREATE OR REPLACE FUNCTION fn_validar_disponibilidad_maquinaria()
RETURNS TRIGGER AS $$
DECLARE
    v_conflicto INT;
BEGIN
    IF NEW.estado_asignacion IN ('Activa', 'Programada') THEN -- primera condicion donde avisamos sobre si esta activa o programada
        SELECT COUNT(*) INTO v_conflicto
        FROM asigna
        WHERE codigo_maquinaria_id = NEW.codigo_maquinaria_id
          AND id_asignacion <> COALESCE(NEW.id_asignacion, -1)
          AND estado_asignacion IN ('Activa', 'Programada')
          AND (
              NEW.fecha_inicio_uso <= COALESCE(fecha_termino_uso, '9999-12-31'::DATE)
              AND COALESCE(NEW.fecha_termino_uso, '9999-12-31'::DATE) >= fecha_inicio_uso
          ); -- aca validamos si si los rangos de fecha no se topan y se puede programar para ese dia

        IF v_conflicto > 0 THEN
            RAISE EXCEPTION 'Conflicto de Maquinaria: El equipo % ya está asignado o programado en otra obra en esas fechas.', 
                NEW.codigo_maquinaria_id;
        END IF; -- aca tenemos la condicion de que si hay conflicto entre los dias, nos avisa de aquello
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_maquinaria
BEFORE INSERT OR UPDATE ON asigna
FOR EACH ROW
EXECUTE FUNCTION fn_validar_disponibilidad_maquinaria();


-- TRIGGER 3: Desnormalización automática en tabla MAQUINARIA
-- Regla: Actualiza en la tabla maquinaria cuál es su obra actual, próxima obra y estado operativo cada vez que cambia la tabla.

CREATE OR REPLACE FUNCTION fn_sincronizar_estado_maquinaria()
RETURNS TRIGGER AS $$
DECLARE
    v_cod_maq VARCHAR(25);
    v_obra_activa VARCHAR(100);
    v_obra_prox VARCHAR(100);
BEGIN
    v_cod_maq := COALESCE(NEW.codigo_maquinaria_id, OLD.codigo_maquinaria_id);

    SELECT a.codigo_obra_id || ' (' || o.direccion || ')' INTO v_obra_activa
    FROM asigna a
    JOIN obra o ON a.codigo_obra_id = o.codigo_obra_id
    WHERE a.codigo_maquinaria_id = v_cod_maq AND a.estado_asignacion = 'Activa'
    LIMIT 1; -- en esta primera parte validamos si esta activa

    
    SELECT a.codigo_obra_id || ' (' || a.fecha_inicio_uso || ')' INTO v_obra_prox
    FROM asigna a
    WHERE a.codigo_maquinaria_id = v_cod_maq AND a.estado_asignacion = 'Programada'
    ORDER BY a.fecha_inicio_uso ASC
    LIMIT 1; -- Buscamos la próxima obra PROGRAMADA más cercana
 
    UPDATE maquinaria
    SET 
        obra_asignada_actual = COALESCE(v_obra_activa, 'Sin asignar'),
        proxima_obra_programada = COALESCE(v_obra_prox, 'Ninguna'),
        estado_actual = CASE 
            WHEN v_obra_activa IS NOT NULL THEN 'En Obra'
            WHEN v_obra_prox IS NOT NULL THEN 'Programada'
            ELSE 'Disponible'
        END
    WHERE codigo_maquinaria_id = v_cod_maq;

    RETURN NULL; -- Actualizamos los campos desnormalizados en la tabla maquinaria
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_actualizar_maquinaria_desnorm
AFTER INSERT OR UPDATE OR DELETE ON asigna
FOR EACH ROW
EXECUTE FUNCTION fn_sincronizar_estado_maquinaria();



-- TRIGGER 4: Desnormalización automática en tabla PAGO (Finanzas)
-- Regla: Guarda el nombre/razón social del cliente directo en el pago para consultar ganancias.

CREATE OR REPLACE FUNCTION fn_sincronizar_cliente_pago()
RETURNS TRIGGER AS $$
BEGIN
    SELECT nombre_razon_social INTO NEW.nombre_cliente_cache
    FROM cliente
    WHERE rut_cliente_id = NEW.rut_cliente_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pago_cliente_cache
BEFORE INSERT OR UPDATE OF rut_cliente_id ON pago
FOR EACH ROW
EXECUTE FUNCTION fn_sincronizar_cliente_pago();