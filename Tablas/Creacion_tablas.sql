-- 1. Tabla de Clientes
CREATE TABLE cliente (
    rut_cliente VARCHAR(12) PRIMARY KEY,
    nombre_razon_social VARCHAR(150) NOT NULL,
    telefono VARCHAR(20),
    correo VARCHAR(100)
);

-- 2. Tabla de Obras (Dependiente de Cliente)
CREATE TABLE obra (
    codigo_obra VARCHAR(20) PRIMARY KEY,
    nombre_obra VARCHAR(150) NOT NULL,
    direccion VARCHAR(250) NOT NULL,
    presupuesto_total NUMERIC(12, 2) NOT NULL CHECK (presupuesto_total > 0),
    rut_cliente VARCHAR(12) NOT NULL,
    CONSTRAINT fk_obra_cliente FOREIGN KEY (rut_cliente) 
        REFERENCES cliente(rut_cliente) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 3. Tabla de Trabajadores (Con campo desnormalizado para la obra actual)
CREATE TABLE trabajador (
    rut_trabajador VARCHAR(12) PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    profesion_cargo VARCHAR(100) NOT NULL,
    salario_base NUMERIC(10, 2) NOT NULL CHECK (salario_base >= 0),
    codigo_obra VARCHAR(20) DEFAULT 'Disponible',
    CONSTRAINT fk_trabajador_obra FOREIGN KEY (codigo_obra) 
        REFERENCES obra(codigo_obra) ON UPDATE CASCADE ON DELETE SET DEFAULT
);

-- 4. Tabla de Maquinaria y Equipos Pesados
CREATE TABLE maquinaria (
    codigo_maquinaria_id VARCHAR(20) PRIMARY KEY,
    modelo VARCHAR(100) NOT NULL,
    marca VARCHAR(100) NOT NULL,
    anio_fabricacion INT CHECK (anio_fabricacion >= 1950),
    costo_por_hora NUMERIC(10, 2) NOT NULL CHECK (costo_por_hora >= 0),
    estado_operativo VARCHAR(30) DEFAULT 'Disponible' CHECK (estado_operativo IN ('Disponible', 'En Obra', 'Programada')),
    codigo_obra VARCHAR(20) DEFAULT 'Sin asignar',
    CONSTRAINT fk_maquinaria_obra FOREIGN KEY (codigo_obra) 
        REFERENCES obra(codigo_obra) ON UPDATE CASCADE ON DELETE SET DEFAULT
);

-- 5. Tabla de Finanzas / Pagos (Con columna caché del cliente para evitar JOINs innecesarios)
CREATE TABLE pago_factura (
    folio VARCHAR(30) PRIMARY KEY,
    codigo_obra VARCHAR(20) NOT NULL,
    rut_cliente VARCHAR(12) NOT NULL,
    nombre_cliente_cache VARCHAR(150) NOT NULL, -- Campo desnormalizado (rellenado por Trigger)
    monto_abono NUMERIC(12, 2) NOT NULL CHECK (monto_abono > 0),
    fecha_pago DATE DEFAULT CURRENT_DATE,
    estado_pago VARCHAR(20) DEFAULT 'Pagado' CHECK (estado_pago IN ('Pagado', 'Pendiente', 'Anulado')),
    CONSTRAINT fk_pago_obra FOREIGN KEY (codigo_obra) 
        REFERENCES obra(codigo_obra) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_pago_cliente FOREIGN KEY (rut_cliente) 
        REFERENCES cliente(rut_cliente) ON UPDATE CASCADE ON DELETE RESTRICT
);
