-- =============================================================================
-- SIGAPE - Banco de dados relacional (versão 7)
-- SGBD: MySQL 8.0.16 ou superior (usa CHECK, colunas geradas, JSON, gatilhos e procedures)
-- Execução: mysql -u root -p < sigape_db_v7.sql   (o cliente mysql entende DELIMITER)
--
-- Criação do zero. Nomes de tabelas no plural, como na versão normalizada da equipe.
-- Ajustes contidos na v7:
--   * Sem homologação: a licença nasce EM_ANDAMENTO (ou AGENDADA, se o início for futuro);
--   * Prazo da licença de saúde livre (definido pela perícia); só os tipos de prazo fixo
--     (maternidade, RN06) são validados contra prazos_licencas;
--   * servidores.id_setor e unidades_exercicio.id_setor ficam coerentes por chave estrangeira composta;
--   * Tabela servidores_vantagens removida. O RH não mantém as vantagens prévias de cada servidor:
--     ao cadastrar a licença, informa só as vantagens que deixam de ser pagas e o valor de cada uma
--     (afastamentos_vantagens). A tabela vantagens continua como catálogo dos tipos de vantagem.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS sigape_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE sigape_db;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 1. ESTRUTURA ORGANIZACIONAL E ACESSO
-- -----------------------------------------------------------------------------

CREATE TABLE setores (
    id_setor INT AUTO_INCREMENT PRIMARY KEY,
    codigo INT NOT NULL,
    nome VARCHAR(100) NOT NULL,
    sigla VARCHAR(20) NOT NULL,             -- usada no número do processo: AAAA.SIGLA.NNNN
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_setor_codigo (codigo),
    UNIQUE KEY uq_setor_sigla (sigla)
) ENGINE=InnoDB;

-- O nome do vínculo é a própria categoria (lista extraída do portal da transparência)
CREATE TABLE vinculos (
    id_vinculo INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    descricao VARCHAR(255) NULL,
    permite_licenca TINYINT(1) NOT NULL DEFAULT 1,   -- 0 = o gatilho recusa licença para este vínculo
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_vinculo_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE situacoes_servidores (
    id_situacao INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    descricao VARCHAR(255) NULL,
    permite_login TINYINT(1) NOT NULL DEFAULT 1,       -- lido pela aplicação no login (RF01)
    permite_afastamento TINYINT(1) NOT NULL DEFAULT 1, -- 0 = o gatilho recusa novas licenças
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_situacao_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE cargos (
    id_cargo INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    codigo_rh VARCHAR(20) NULL,                  -- código correspondente no RH 247
    descricao VARCHAR(255) NULL,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_cargo_nome (nome),
    UNIQUE KEY uq_cargo_codigo (codigo_rh)
) ENGINE=InnoDB;

CREATE TABLE unidades_exercicio (
    id_unidade INT AUTO_INCREMENT PRIMARY KEY,
    id_setor INT NOT NULL,                      -- secretaria a que a unidade pertence
    nome VARCHAR(150) NOT NULL,
    codigo_rh VARCHAR(20) NULL,
    endereco VARCHAR(255) NULL,
    telefone VARCHAR(20) NULL,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_unidade_nome (nome),
    UNIQUE KEY uq_unidade_setor (id_unidade, id_setor),   -- alvo da chave composta de servidores
    CONSTRAINT fk_unidades_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE servidores (
    id_servidor INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    cpf CHAR(11) NOT NULL,
    matricula VARCHAR(50) NOT NULL,
    id_cargo INT NOT NULL,
    id_vinculo INT NOT NULL,
    id_situacao INT NOT NULL,
    -- RN25 / RF34 / RF35: o autocadastro fica pendente até o RH conferir
    situacao_cadastro ENUM('VALIDADO', 'PENDENTE_VALIDACAO', 'CONFLITO', 'REJEITADO') NOT NULL DEFAULT 'VALIDADO',
    origem_cadastro ENUM('IMPORTACAO', 'MANUAL', 'AUTOCADASTRO') NOT NULL DEFAULT 'MANUAL',
    data_admissao DATE NOT NULL,
    telefone VARCHAR(20) NULL,
    email VARCHAR(100) NULL,
    endereco VARCHAR(255) NULL,                 -- formatado pelo front-end
    id_unidade_exercicio INT NULL,
    id_setor INT NOT NULL,                      -- setor de lotação; também define o setor de atuação do usuário
    id_usuario_validacao INT NULL,
    data_validacao DATETIME NULL,
    data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_atualizacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_servidor_cpf (cpf),
    UNIQUE KEY uq_servidor_matricula (matricula),
    KEY idx_servidor_nome (nome),
    KEY idx_servidor_setor (id_setor),
    KEY idx_servidor_cadastro (situacao_cadastro),
    CONSTRAINT fk_servidores_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_servidores_vinculo FOREIGN KEY (id_vinculo) REFERENCES vinculos (id_vinculo) ON DELETE RESTRICT,
    CONSTRAINT fk_servidores_situacao FOREIGN KEY (id_situacao) REFERENCES situacoes_servidores (id_situacao) ON DELETE RESTRICT,
    CONSTRAINT fk_servidores_cargo FOREIGN KEY (id_cargo) REFERENCES cargos (id_cargo) ON DELETE RESTRICT,
    -- A unidade de exercício precisa ser do mesmo setor do servidor. Se a unidade for nula, nada é conferido.
    CONSTRAINT fk_servidores_unidade_setor FOREIGN KEY (id_unidade_exercicio, id_setor)
        REFERENCES unidades_exercicio (id_unidade, id_setor) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- O login é pela matrícula do servidor (RF01); o e-mail fica em servidores.
CREATE TABLE usuarios (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    id_servidor INT NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,           -- bcrypt, custo >= 12 (RNF08)
    perfil ENUM('servidor_comum', 'operador_setor', 'gestor_setor', 'admin_sistema') NOT NULL DEFAULT 'servidor_comum',
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    tentativas_falhas INT UNSIGNED NOT NULL DEFAULT 0,
    bloqueado_ate DATETIME NULL,
    data_ultimo_acesso DATETIME NULL,
    data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_usuario_servidor (id_servidor),
    CONSTRAINT fk_usuarios_servidor FOREIGN KEY (id_servidor) REFERENCES servidores (id_servidor) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Referência circular: quem validou o cadastro
ALTER TABLE servidores
    ADD CONSTRAINT fk_servidores_usuario_validacao
    FOREIGN KEY (id_usuario_validacao) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT;

-- Links de uso único (RF02 e RF34). Guarda-se o hash do link, nunca o link.
CREATE TABLE tokens_acesso (
    id_token INT AUTO_INCREMENT PRIMARY KEY,
    finalidade ENUM('RECUPERACAO_SENHA', 'AUTOCADASTRO') NOT NULL,
    hash_token CHAR(64) NOT NULL,
    id_servidor INT NULL,
    email_destino VARCHAR(100) NOT NULL,
    dados_cadastro JSON NULL,                   -- dados do autocadastro até a confirmação
    expira_em DATETIME NOT NULL,
    usado_em DATETIME NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_token_hash (hash_token),
    KEY idx_token_expira (expira_em),
    CONSTRAINT fk_tokens_servidor FOREIGN KEY (id_servidor) REFERENCES servidores (id_servidor) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE parametros (
    chave VARCHAR(60) PRIMARY KEY,
    valor VARCHAR(100) NOT NULL,
    descricao VARCHAR(255) NULL
) ENGINE=InnoDB;

-- Contador para números únicos: processo (por setor e ano), documento oficial e documento no processo
CREATE TABLE sequencias (
    id_sequencia INT AUTO_INCREMENT PRIMARY KEY,
    escopo VARCHAR(30) NOT NULL,                -- PROCESSO, DOC_OFICIAL ou DOC_PROCESSO
    id_setor INT NOT NULL DEFAULT 0,
    id_referencia INT NOT NULL DEFAULT 0,       -- tipo de documento (DOC_OFICIAL) ou processo (DOC_PROCESSO)
    ano SMALLINT NOT NULL DEFAULT 0,
    ultimo_numero INT UNSIGNED NOT NULL DEFAULT 0,
    UNIQUE KEY uq_sequencia (escopo, id_setor, id_referencia, ano)
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- 2. SIGAPE-PROTOCOLO
-- -----------------------------------------------------------------------------

CREATE TABLE tipos_processos (
    id_tipo_processo INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    descricao VARCHAR(255) NULL,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_tipo_processo_nome (nome)
) ENGINE=InnoDB;

-- RF33: 'Conclusão exclusiva do setor' aceita um ou mais setores.
-- Sem linhas para o tipo, qualquer setor que detenha a posse pode concluir.
CREATE TABLE tipos_processos_setores_conclusao (
    id_tipo_processo INT NOT NULL,
    id_setor INT NOT NULL,
    PRIMARY KEY (id_tipo_processo, id_setor),
    CONSTRAINT fk_tpsc_tipo FOREIGN KEY (id_tipo_processo) REFERENCES tipos_processos (id_tipo_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_tpsc_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE catalogos_assuntos (
    id_assunto INT AUTO_INCREMENT PRIMARY KEY,
    id_tipo_processo INT NOT NULL,
    descricao VARCHAR(150) NOT NULL,
    prazo_dias_padrao INT UNSIGNED NOT NULL DEFAULT 15,    -- prazo de retorno padrão (RF27)
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_assunto (id_tipo_processo, descricao),
    CONSTRAINT fk_assuntos_tipo_processo FOREIGN KEY (id_tipo_processo) REFERENCES tipos_processos (id_tipo_processo) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE processos (
    id_processo INT AUTO_INCREMENT PRIMARY KEY,
    numero_protocolo VARCHAR(50) NOT NULL,                  -- AAAA.SETOR.NNNN (RN16)
    id_tipo_processo INT NOT NULL,
    id_assunto INT NOT NULL,
    servidor_interessado_id INT NOT NULL,
    usuario_abertura_id INT NOT NULL,
    setor_origem_id INT NOT NULL,                           -- setor que abriu; entra no número
    setor_atual_id INT NOT NULL,                            -- setor que detém a posse (RN17)
    descricao_justificativa TEXT NOT NULL,
    nivel_acesso ENUM('PUBLICO', 'PRIVADO') NOT NULL DEFAULT 'PUBLICO',
    status ENUM('EM_ANDAMENTO', 'CONCLUIDO', 'CANCELADO', 'ARQUIVADO') NOT NULL DEFAULT 'EM_ANDAMENTO',
    data_abertura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_encerramento DATETIME NULL,
    data_atualizacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_processo_numero (numero_protocolo),
    KEY idx_processo_posse (setor_atual_id, status),
    KEY idx_processo_origem (setor_origem_id, status),
    KEY idx_processo_interessado (servidor_interessado_id),
    KEY idx_processo_abertura (data_abertura),
    CONSTRAINT fk_procs_tipo FOREIGN KEY (id_tipo_processo) REFERENCES tipos_processos (id_tipo_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_procs_assunto FOREIGN KEY (id_assunto) REFERENCES catalogos_assuntos (id_assunto) ON DELETE RESTRICT,
    CONSTRAINT fk_procs_interessado FOREIGN KEY (servidor_interessado_id) REFERENCES servidores (id_servidor) ON DELETE RESTRICT,
    CONSTRAINT fk_procs_usuario_abertura FOREIGN KEY (usuario_abertura_id) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_procs_setor_origem FOREIGN KEY (setor_origem_id) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_procs_setor_atual FOREIGN KEY (setor_atual_id) REFERENCES setores (id_setor) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE tipos_documentos (
    id_tipo_documento INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    gera_numeracao_oficial TINYINT(1) NOT NULL DEFAULT 0,  -- 1 = número TIPO-SETOR-NNNN/AAAA (RN05)
    sigla_documento VARCHAR(20) NULL,
    nivel_acesso_padrao ENUM('PUBLICO', 'PRIVADO') NOT NULL DEFAULT 'PUBLICO',
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_tipo_documento_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE documentos (
    id_documento INT AUTO_INCREMENT PRIMARY KEY,
    id_processo INT NOT NULL,
    id_tipo_documento INT NOT NULL,
    numero_sequencial_processo INT UNSIGNED NOT NULL,      -- 1, 2, 3... (00001 na tela)
    numero_documento_oficial VARCHAR(50) NULL,
    titulo_ou_nome_arquivo VARCHAR(255) NOT NULL,
    conteudo_texto LONGTEXT NULL,                         -- quando escrito no editor interno
    caminho_storage VARCHAR(255) NULL,                     -- quando enviado como arquivo (guardado fora do banco)
    mime_type VARCHAR(100) NULL,
    tamanho_bytes INT UNSIGNED NULL,
    hash_sha256 CHAR(64) NULL,                             -- preenchido ao finalizar (RNF15)
    nivel_acesso ENUM('PUBLICO', 'PRIVADO') NOT NULL DEFAULT 'PUBLICO',
    status ENUM('RASCUNHO', 'FINALIZADO', 'ASSINADO', 'EXCLUIDO') NOT NULL DEFAULT 'FINALIZADO',  -- ASSINADO a partir da 1ª assinatura
    id_documento_corrigido INT NULL,                        -- RN18: a correção é um novo documento
    id_usuario_upload INT NOT NULL,
    data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_doc_numero_processo (id_processo, numero_sequencial_processo),
    UNIQUE KEY uq_doc_numero_oficial (numero_documento_oficial),
    KEY idx_doc_processo (id_processo),
    CONSTRAINT chk_doc_tamanho CHECK (tamanho_bytes IS NULL OR tamanho_bytes <= 15728640),   -- 15 MB (RF20)
    CONSTRAINT fk_docs_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_docs_tipo FOREIGN KEY (id_tipo_documento) REFERENCES tipos_documentos (id_tipo_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_docs_corrigido FOREIGN KEY (id_documento_corrigido) REFERENCES documentos (id_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_docs_usuario_up FOREIGN KEY (id_usuario_upload) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Assinaturas eletrônicas simples (RF22, Lei 14.063/2020). Um documento pode ter várias; cada linha é imutável.
CREATE TABLE assinaturas_documentos (
    id_assinatura INT AUTO_INCREMENT PRIMARY KEY,
    id_documento INT NOT NULL,
    id_usuario INT NOT NULL,
    id_setor INT NOT NULL,                                 -- setor do usuário no momento da assinatura
    hash_sha256 CHAR(64) NOT NULL,                         -- hash do documento no momento em que foi assinado
    dados_carimbo JSON NOT NULL,                           -- nome, matrícula, cargo e setor na hora (RF22.2)
    data_assinatura DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_assinatura_usuario (id_documento, id_usuario),
    KEY idx_assin_usuario (id_usuario),
    CONSTRAINT fk_assin_documento FOREIGN KEY (id_documento) REFERENCES documentos (id_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_assin_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_assin_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Histórico imutável dos envios entre setores (RF25). manter_visivel guarda a escolha feita no envio.
CREATE TABLE tramitacoes (
    id_tramitacao INT AUTO_INCREMENT PRIMARY KEY,
    id_processo INT NOT NULL,
    setor_origem_id INT NOT NULL,
    setor_destino_id INT NOT NULL,
    usuario_envio_id INT NOT NULL,
    manter_visivel TINYINT(1) NOT NULL DEFAULT 0,
    prazo_retorno DATE NULL,
    data_tramitacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_tram_processo (id_processo, data_tramitacao),
    KEY idx_tram_destino (setor_destino_id),
    KEY idx_tram_origem (setor_origem_id),
    CONSTRAINT chk_tram_setores CHECK (setor_origem_id <> setor_destino_id),
    CONSTRAINT fk_trams_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_trams_origem FOREIGN KEY (setor_origem_id) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_trams_destino FOREIGN KEY (setor_destino_id) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_trams_usuario FOREIGN KEY (usuario_envio_id) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Visibilidade em leitura para o setor que enviou e escolheu manter o processo (RF25, RF26).
CREATE TABLE processos_setores_visibilidade (
    id_visibilidade INT AUTO_INCREMENT PRIMARY KEY,
    id_processo INT NOT NULL,
    id_setor INT NOT NULL,
    id_tramitacao_origem INT NOT NULL,                     -- envio em que o setor escolheu manter
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    data_vinculo DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_remocao DATETIME NULL,
    id_usuario_remocao INT NULL,
    UNIQUE KEY uq_processo_setor_visivel (id_processo, id_setor),
    KEY idx_psv_setor_ativo (id_setor, ativo),
    CONSTRAINT fk_psv_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_psv_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_psv_tramitacao FOREIGN KEY (id_tramitacao_origem) REFERENCES tramitacoes (id_tramitacao) ON DELETE RESTRICT,
    CONSTRAINT fk_psv_usuario_remocao FOREIGN KEY (id_usuario_remocao) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Linha do tempo do processo (RF24): tudo o que acontece, em ordem, sem alteração
CREATE TABLE andamentos (
    id_andamento BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_processo INT NOT NULL,
    data_hora DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    id_setor INT NOT NULL,
    id_usuario INT NOT NULL,
    tipo_evento ENUM('PROCESSO_GERADO', 'DOCUMENTO_INSERIDO', 'DOCUMENTO_ASSINADO', 'PROCESSO_ENVIADO',
                     'PROCESSO_CONCLUIDO', 'PROCESSO_REABERTO', 'PROCESSO_CANCELADO',
                     'PROCESSO_ARQUIVADO', 'PROCESSO_DESARQUIVADO', 'NIVEL_ACESSO_ALTERADO', 'OUTRO') NOT NULL,
    descricao VARCHAR(500) NOT NULL,
    justificativa VARCHAR(500) NULL,                       -- obrigatória ao reabrir, cancelar e arquivar (RF29)
    id_documento INT NULL,
    id_tramitacao INT NULL,
    KEY idx_andamento_processo (id_processo, data_hora),
    CONSTRAINT fk_ands_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_ands_setor FOREIGN KEY (id_setor) REFERENCES setores (id_setor) ON DELETE RESTRICT,
    CONSTRAINT fk_ands_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_ands_documento FOREIGN KEY (id_documento) REFERENCES documentos (id_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_ands_tramitacao FOREIGN KEY (id_tramitacao) REFERENCES tramitacoes (id_tramitacao) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Códigos de verificação dos PDFs exportados (RF31 e RF32).
CREATE TABLE verificacoes_documentos (
    id_verificacao INT AUTO_INCREMENT PRIMARY KEY,
    codigo CHAR(32) NOT NULL,
    tipo_alvo VARCHAR(20) NOT NULL,                        -- DOCUMENTO ou PROCESSO
    id_processo INT NOT NULL,
    id_documento INT NULL,
    hash_sha256 CHAR(64) NOT NULL,
    id_usuario_geracao INT NOT NULL,
    data_geracao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_verificacao_codigo (codigo),
    KEY idx_verificacao_processo (id_processo),
    CONSTRAINT fk_verif_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_verif_documento FOREIGN KEY (id_documento) REFERENCES documentos (id_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_verif_usuario FOREIGN KEY (id_usuario_geracao) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- 3. SIGAPE-AFASTAMENTOS
-- -----------------------------------------------------------------------------

-- Catálogo dos tipos de vantagem. O RH não guarda as vantagens prévias de cada servidor no sistema.
CREATE TABLE vantagens (
    id_vantagem INT AUTO_INCREMENT PRIMARY KEY,
    nome_vantagem VARCHAR(100) NOT NULL,
    descricao VARCHAR(255) NULL,
    presencial_padrao TINYINT(1) NOT NULL DEFAULT 1,       -- vantagem ligada ao trabalho presencial (RN03)
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_vantagem_nome (nome_vantagem)
) ENGINE=InnoDB;

CREATE TABLE importacoes (
    id_importacao INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    nome_arquivo VARCHAR(255) NOT NULL,
    versao_layout VARCHAR(20) NOT NULL,                    -- RNF29
    status ENUM('CONCLUIDA', 'REJEITADA') NOT NULL,
    total_lidos INT UNSIGNED NOT NULL DEFAULT 0,
    total_inseridos INT UNSIGNED NOT NULL DEFAULT 0,
    total_atualizados INT UNSIGNED NOT NULL DEFAULT 0,
    total_rejeitados INT UNSIGNED NOT NULL DEFAULT 0,
    data_importacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_imps_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE importacoes_erros (
    id_erro INT AUTO_INCREMENT PRIMARY KEY,
    id_importacao INT NOT NULL,
    linha INT UNSIGNED NOT NULL,
    campo VARCHAR(50) NOT NULL,
    mensagem VARCHAR(255) NOT NULL,
    KEY idx_imp_erro (id_importacao),
    CONSTRAINT fk_imperro_importacao FOREIGN KEY (id_importacao) REFERENCES importacoes (id_importacao) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Tipos de licença (RN06, RN07). Saúde: prazo livre, definido pela perícia. Maternidade: prazo fixo por vínculo.
CREATE TABLE tipos_licencas (
    id_tipo_licenca INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    prazo_fixo TINYINT(1) NOT NULL DEFAULT 0,              -- 1 = só valem os dias de prazos_licencas para o vínculo
    suspende_vantagens TINYINT(1) NOT NULL DEFAULT 0,      -- RN03
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_tipo_licenca_nome (nome)
) ENGINE=InnoDB;

-- Dias permitidos por vínculo, só para os tipos de prazo fixo
CREATE TABLE prazos_licencas (
    id_prazo INT AUTO_INCREMENT PRIMARY KEY,
    id_tipo_licenca INT NOT NULL,
    id_vinculo INT NOT NULL,
    dias SMALLINT UNSIGNED NOT NULL,
    descricao_opcao VARCHAR(50) NULL,                      -- texto da opção na tela, ex.: '120 dias'
    UNIQUE KEY uq_prazo (id_tipo_licenca, id_vinculo, dias),
    CONSTRAINT fk_prazos_tipo FOREIGN KEY (id_tipo_licenca) REFERENCES tipos_licencas (id_tipo_licenca) ON DELETE RESTRICT,
    CONSTRAINT fk_prazos_vinculo FOREIGN KEY (id_vinculo) REFERENCES vinculos (id_vinculo) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE afastamentos (
    id_afastamento INT AUTO_INCREMENT PRIMARY KEY,
    id_servidor INT NOT NULL,
    id_tipo_licenca INT NOT NULL,
    data_inicio DATE NOT NULL,
    quantidade_dias SMALLINT UNSIGNED NOT NULL,
    data_fim DATE GENERATED ALWAYS AS (DATE_ADD(data_inicio, INTERVAL quantidade_dias - 1 DAY)) STORED,
    data_retorno_prevista DATE GENERATED ALWAYS AS (DATE_ADD(data_inicio, INTERVAL quantidade_dias DAY)) STORED,
    data_retorno_efetivo DATETIME NULL,                    -- RF13: data e hora do retorno confirmado
    id_usuario_retorno INT NULL,
    motivo_observacao TEXT NULL,                            -- não registrar o nome da doença (Estatuto, art. 95)
    id_processo_origem INT NULL,                            -- embasamento: processo ou requerimento
    id_documento_laudo INT NULL,                            -- laudo ou atestado da perícia anexado (opcional)
    status ENUM('AGENDADA', 'EM_ANDAMENTO', 'ENCERRADO', 'PRORROGADO', 'CANCELADO')
        NOT NULL DEFAULT 'EM_ANDAMENTO',                    -- AGENDADA: início futuro
    id_usuario_registro INT NOT NULL,
    id_afastamento_original INT NULL,                      -- prorrogação aponta para a licença original (RF14)
    data_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_afast_servidor (id_servidor, data_inicio),
    KEY idx_afast_status_fim (status, data_fim),
    CONSTRAINT chk_afast_dias CHECK (quantidade_dias > 0),
    CONSTRAINT fk_afasts_servidor FOREIGN KEY (id_servidor) REFERENCES servidores (id_servidor) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_tipo FOREIGN KEY (id_tipo_licenca) REFERENCES tipos_licencas (id_tipo_licenca) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_processo FOREIGN KEY (id_processo_origem) REFERENCES processos (id_processo) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_laudo FOREIGN KEY (id_documento_laudo) REFERENCES documentos (id_documento) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_usuario_retorno FOREIGN KEY (id_usuario_retorno) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_usuario FOREIGN KEY (id_usuario_registro) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_afasts_original FOREIGN KEY (id_afastamento_original) REFERENCES afastamentos (id_afastamento) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Vantagens que deixam de ser pagas durante a licença (RF09). O RH escolhe o tipo e informa o valor na hora
-- de cadastrar a licença; não há cadastro prévio das vantagens de cada servidor.
CREATE TABLE afastamentos_vantagens (
    id_afastamento_vantagem INT AUTO_INCREMENT PRIMARY KEY,
    id_afastamento INT NOT NULL,
    id_vantagem INT NOT NULL,
    valor_suspenso DECIMAL(10,2) NOT NULL,
    status_vantagem ENUM('SUSPENSA', 'REATIVADA') NOT NULL DEFAULT 'SUSPENSA',
    UNIQUE KEY uq_afast_vantagem (id_afastamento, id_vantagem),
    CONSTRAINT fk_avs_afastamento FOREIGN KEY (id_afastamento) REFERENCES afastamentos (id_afastamento) ON DELETE RESTRICT,
    CONSTRAINT fk_avs_vantagem FOREIGN KEY (id_vantagem) REFERENCES vantagens (id_vantagem) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Ordens em PDF para o operador da folha aplicar no RH 247 (RF10 e RF13)
CREATE TABLE ordens_folhas (
    id_ordem INT AUTO_INCREMENT PRIMARY KEY,
    id_afastamento INT NOT NULL,
    tipo ENUM('SUSPENSAO', 'REATIVACAO') NOT NULL,
    competencia CHAR(7) NULL,                              -- AAAA-MM da folha seguinte (reativação)
    caminho_pdf VARCHAR(255) NOT NULL,
    hash_sha256 CHAR(64) NOT NULL,
    id_usuario_geracao INT NOT NULL,
    data_geracao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_ordem_afast (id_afastamento),
    CONSTRAINT fk_ordens_afastamento FOREIGN KEY (id_afastamento) REFERENCES afastamentos (id_afastamento) ON DELETE RESTRICT,
    CONSTRAINT fk_ordens_usuario FOREIGN KEY (id_usuario_geracao) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE notificacoes (
    id_notificacao INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NOT NULL,
    id_afastamento INT NULL,
    id_processo INT NULL,
    titulo VARCHAR(100) NOT NULL,
    mensagem VARCHAR(500) NOT NULL,
    tipo_notificacao VARCHAR(50) NOT NULL DEFAULT 'GERAL',
    lida TINYINT(1) NOT NULL DEFAULT 0,
    data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_leitura DATETIME NULL,
    UNIQUE KEY uq_alerta_unico (id_usuario, id_afastamento, tipo_notificacao),
    KEY idx_notif_usuario (id_usuario, lida),
    KEY idx_notif_tipo (tipo_notificacao),
    CONSTRAINT fk_notifs_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT,
    CONSTRAINT fk_notifs_afastamento FOREIGN KEY (id_afastamento) REFERENCES afastamentos (id_afastamento) ON DELETE RESTRICT,
    CONSTRAINT fk_notifs_processo FOREIGN KEY (id_processo) REFERENCES processos (id_processo) ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE envios_emails (
    id_envio INT AUTO_INCREMENT PRIMARY KEY,
    id_notificacao INT NULL,
    finalidade VARCHAR(50) NOT NULL,                       -- ex.: ALERTA_TERMINO, RECUPERACAO_SENHA, AUTOCADASTRO
    destinatario VARCHAR(100) NOT NULL,
    assunto VARCHAR(150) NULL,
    modelo VARCHAR(50) NULL,                               -- nome do modelo de e-mail usado
    parametros JSON NULL,                                  -- dados do modelo, nunca o link nem a senha
    status ENUM('PENDENTE', 'ENVIADO', 'FALHA') NOT NULL DEFAULT 'PENDENTE',
    tentativas TINYINT UNSIGNED NOT NULL DEFAULT 0,
    ultimo_erro VARCHAR(255) NULL,
    data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_envio DATETIME NULL,
    KEY idx_envio_status (status, data_criacao),
    CONSTRAINT fk_envios_notificacao FOREIGN KEY (id_notificacao) REFERENCES notificacoes (id_notificacao) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- 4. AUDITORIA (RNF14)
-- -----------------------------------------------------------------------------

CREATE TABLE logs_auditoria (
    id_log BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_usuario INT NULL,
    ip_origem VARCHAR(45) NOT NULL,
    acao VARCHAR(100) NOT NULL,
    entidade_afetada VARCHAR(50) NOT NULL,
    id_registro_afetado BIGINT NOT NULL,
    valor_anterior JSON NULL,
    valor_novo JSON NULL,                                  -- sem senhas e sem conteúdo de laudos
    hash_anterior CHAR(64) NULL,
    hash_atual CHAR(64) NOT NULL,
    data_hora DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    KEY idx_log_entidade (entidade_afetada, id_registro_afetado),
    KEY idx_log_usuario (id_usuario, data_hora),
    CONSTRAINT fk_logs_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios (id_usuario) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- -----------------------------------------------------------------------------
-- 5. PROCEDURES E VISÕES
-- -----------------------------------------------------------------------------

DELIMITER $$

CREATE PROCEDURE proximo_numero(
    IN p_escopo VARCHAR(30), IN p_setor INT, IN p_ref INT, IN p_ano SMALLINT, OUT p_numero INT UNSIGNED)
BEGIN
    INSERT INTO sequencias (escopo, id_setor, id_referencia, ano, ultimo_numero)
    VALUES (p_escopo, p_setor, p_ref, p_ano, 1)
    ON DUPLICATE KEY UPDATE ultimo_numero = LAST_INSERT_ID(ultimo_numero + 1);
    IF ROW_COUNT() = 1 THEN
        SET p_numero = 1;
    ELSE
        SET p_numero = LAST_INSERT_ID();
    END IF;
END$$

CREATE PROCEDURE tramitar_processo(
    IN p_id_processo INT, IN p_id_usuario INT, IN p_setor_destino INT,
    IN p_observacao TEXT, IN p_manter_visivel TINYINT, IN p_prazo_retorno DATE)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_setor_atual INT;
    DECLARE v_setor_usuario INT;
    DECLARE v_destino_ativo TINYINT;
    DECLARE v_sigla VARCHAR(20);
    DECLARE v_docs INT;
    DECLARE v_id_tram INT;
    DECLARE v_obs TEXT;

    SET v_obs = NULLIF(TRIM(p_observacao), '');
    IF CHAR_LENGTH(v_obs) > 255 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'a observacao do envio deve ter no maximo 255 caracteres';
    END IF;

    SELECT status, setor_atual_id INTO v_status, v_setor_atual
      FROM processos WHERE id_processo = p_id_processo FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'processo inexistente';
    END IF;
    IF v_status <> 'EM_ANDAMENTO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'so processo em andamento pode ser tramitado';
    END IF;

    SELECT s.id_setor INTO v_setor_usuario
      FROM usuarios u JOIN servidores s ON s.id_servidor = u.id_servidor
     WHERE u.id_usuario = p_id_usuario;
    IF v_setor_usuario IS NULL OR v_setor_usuario <> v_setor_atual THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN17: so o setor que detem a posse pode tramitar o processo';
    END IF;

    SELECT ativo, sigla INTO v_destino_ativo, v_sigla FROM setores WHERE id_setor = p_setor_destino;
    IF v_destino_ativo IS NULL OR v_destino_ativo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'setor de destino invalido ou inativo';
    END IF;
    IF p_setor_destino = v_setor_atual THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'o setor de destino e o setor atual do processo';
    END IF;

    SELECT COUNT(*) INTO v_docs FROM documentos WHERE id_processo = p_id_processo AND status <> 'EXCLUIDO';
    IF v_docs = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN17: processo sem documentos nao pode ser tramitado';
    END IF;

    UPDATE processos SET setor_atual_id = p_setor_destino WHERE id_processo = p_id_processo;

    INSERT INTO tramitacoes (id_processo, setor_origem_id, setor_destino_id, usuario_envio_id,
                             manter_visivel, prazo_retorno)
    VALUES (p_id_processo, v_setor_atual, p_setor_destino, p_id_usuario,
            IFNULL(p_manter_visivel, 0), p_prazo_retorno);
    SET v_id_tram = LAST_INSERT_ID();

    INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao, id_tramitacao)
    VALUES (p_id_processo, v_setor_atual, p_id_usuario, 'PROCESSO_ENVIADO',
            CONCAT('Processo enviado para ', v_sigla, '.',
                   IF(v_obs IS NULL, '', CONCAT(' Obs.: ', v_obs))), v_id_tram);

    IF IFNULL(p_manter_visivel, 0) = 1 THEN
        INSERT INTO processos_setores_visibilidade (id_processo, id_setor, id_tramitacao_origem)
        VALUES (p_id_processo, v_setor_atual, v_id_tram)
        ON DUPLICATE KEY UPDATE ativo = 1, data_remocao = NULL, id_usuario_remocao = NULL,
                                id_tramitacao_origem = v_id_tram, data_vinculo = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE PROCEDURE remover_visibilidade_processo(IN p_id_processo INT, IN p_id_usuario INT)
BEGIN
    DECLARE v_setor_usuario INT;
    DECLARE v_id_visibilidade INT;
    DECLARE v_ativo TINYINT;

    SELECT s.id_setor INTO v_setor_usuario
      FROM usuarios u JOIN servidores s ON s.id_servidor = u.id_servidor
     WHERE u.id_usuario = p_id_usuario;
    IF v_setor_usuario IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'usuario inexistente';
    END IF;

    SELECT id_visibilidade, ativo INTO v_id_visibilidade, v_ativo
      FROM processos_setores_visibilidade
     WHERE id_processo = p_id_processo AND id_setor = v_setor_usuario FOR UPDATE;
    IF v_id_visibilidade IS NULL OR v_ativo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'o setor nao mantem este processo na caixa de acompanhamento';
    END IF;

    UPDATE processos_setores_visibilidade
       SET ativo = 0, data_remocao = CURRENT_TIMESTAMP, id_usuario_remocao = p_id_usuario
     WHERE id_visibilidade = v_id_visibilidade;
END$$

CREATE PROCEDURE assinar_documento(
    IN p_id_documento INT, IN p_id_usuario INT, IN p_dados_carimbo JSON)
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_id_processo INT;
    DECLARE v_id_tipo INT;
    DECLARE v_hash CHAR(64);
    DECLARE v_numero_oficial VARCHAR(50);
    DECLARE v_seq_processo INT UNSIGNED;
    DECLARE v_proc_status VARCHAR(20);
    DECLARE v_setor_atual INT;
    DECLARE v_gera TINYINT;
    DECLARE v_sigla_doc VARCHAR(20);
    DECLARE v_setor_usuario INT;
    DECLARE v_sigla_setor VARCHAR(20);
    DECLARE v_usuario_ativo TINYINT;
    DECLARE v_total INT;
    DECLARE v_n INT UNSIGNED;

    IF p_dados_carimbo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'dados do carimbo nao informados';
    END IF;

    SELECT status, id_processo, id_tipo_documento, hash_sha256, numero_documento_oficial, numero_sequencial_processo
      INTO v_status, v_id_processo, v_id_tipo, v_hash, v_numero_oficial, v_seq_processo
      FROM documentos WHERE id_documento = p_id_documento FOR UPDATE;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'documento inexistente';
    END IF;
    IF v_status NOT IN ('FINALIZADO', 'ASSINADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'so documento finalizado pode ser assinado';
    END IF;
    IF v_hash IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF15: documento sem hash nao pode ser assinado';
    END IF;

    SELECT status, setor_atual_id INTO v_proc_status, v_setor_atual
      FROM processos WHERE id_processo = v_id_processo;
    IF v_proc_status <> 'EM_ANDAMENTO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'so se assina documento de processo em andamento';
    END IF;

    SELECT s.id_setor, st.sigla, u.ativo INTO v_setor_usuario, v_sigla_setor, v_usuario_ativo
      FROM usuarios u
      JOIN servidores s ON s.id_servidor = u.id_servidor
      JOIN setores st ON st.id_setor = s.id_setor
     WHERE u.id_usuario = p_id_usuario;
    IF v_setor_usuario IS NULL OR v_usuario_ativo = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'usuario inexistente ou inativo';
    END IF;
    IF v_setor_usuario <> v_setor_atual THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN17: so o setor que detem a posse do processo pode assinar';
    END IF;

    SELECT COUNT(*) INTO v_total FROM assinaturas_documentos
     WHERE id_documento = p_id_documento AND id_usuario = p_id_usuario;
    IF v_total > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'o usuario ja assinou este documento';
    END IF;

    INSERT INTO assinaturas_documentos (id_documento, id_usuario, id_setor, hash_sha256, dados_carimbo)
    VALUES (p_id_documento, p_id_usuario, v_setor_usuario, v_hash, p_dados_carimbo);

    IF v_status = 'FINALIZADO' THEN
        SELECT gera_numeracao_oficial, sigla_documento INTO v_gera, v_sigla_doc
          FROM tipos_documentos WHERE id_tipo_documento = v_id_tipo;

        IF v_gera = 1 AND v_numero_oficial IS NULL THEN
            CALL proximo_numero('DOC_OFICIAL', v_setor_usuario, v_id_tipo, YEAR(NOW()), v_n);
            SET v_numero_oficial = CONCAT(v_sigla_doc, '-', v_sigla_setor, '-', LPAD(v_n, 4, '0'), '/', YEAR(NOW()));
        END IF;

        UPDATE documentos
           SET status = 'ASSINADO', numero_documento_oficial = v_numero_oficial
         WHERE id_documento = p_id_documento;
    END IF;

    INSERT INTO andamentos (id_processo, id_setor, id_usuario, tipo_evento, descricao, id_documento)
    VALUES (v_id_processo, v_setor_usuario, p_id_usuario, 'DOCUMENTO_ASSINADO',
            CONCAT('Documento ', LPAD(v_seq_processo, 5, '0'),
                   IF(v_numero_oficial IS NULL, '', CONCAT(' (', v_numero_oficial, ')')), ' assinado.'),
            p_id_documento);
END$$

DELIMITER ;

-- Situação de cada licença: retorno pendente (RF13) e término próximo (RF11)
CREATE VIEW vw_afastamento_situacao AS
SELECT a.*,
       s.nome AS servidor_nome,
       s.matricula,
       CASE
         WHEN a.status IN ('EM_ANDAMENTO', 'PRORROGADO') AND a.data_retorno_efetivo IS NULL
              AND a.data_retorno_prevista < CURDATE() THEN 'RETORNO_PENDENTE'
         WHEN a.status = 'EM_ANDAMENTO'
              AND DATEDIFF(a.data_fim, CURDATE()) BETWEEN 0 AND
                  (SELECT CAST(valor AS UNSIGNED) FROM parametros WHERE chave = 'ALERTA_TERMINO_DIAS') THEN 'TERMINO_PROXIMO'
         ELSE NULL
       END AS situacao_prazo
FROM afastamentos a
JOIN servidores s ON s.id_servidor = a.id_servidor;

-- Última tramitação de cada processo em andamento e se o prazo de retorno venceu (RF27)
CREATE VIEW vw_tramitacao_atual AS
SELECT t.*,
       (t.prazo_retorno IS NOT NULL AND t.prazo_retorno < CURDATE()) AS prazo_vencido
FROM tramitacoes t
JOIN processos p ON p.id_processo = t.id_processo AND p.status = 'EM_ANDAMENTO'
WHERE t.id_tramitacao = (SELECT MAX(t2.id_tramitacao) FROM tramitacoes t2 WHERE t2.id_processo = t.id_processo);

-- Caixas do setor (RF28). Filtre por id_setor_caixa.
CREATE VIEW vw_caixa_entrada AS
SELECT p.*, p.setor_atual_id AS id_setor_caixa
FROM processos p
WHERE p.status = 'EM_ANDAMENTO';

CREATE VIEW vw_caixa_acompanhamento AS
SELECT p.*, v.id_setor AS id_setor_caixa
FROM processos_setores_visibilidade v
JOIN processos p ON p.id_processo = v.id_processo
WHERE v.ativo = 1 AND p.status = 'EM_ANDAMENTO' AND p.setor_atual_id <> v.id_setor;

CREATE VIEW vw_processos_do_setor AS
SELECT p.*, p.setor_origem_id AS id_setor_caixa FROM processos p
UNION
SELECT p.*, p.setor_atual_id FROM processos p
UNION
SELECT p.*, t.setor_origem_id FROM processos p JOIN tramitacoes t ON t.id_processo = p.id_processo
UNION
SELECT p.*, t.setor_destino_id FROM processos p JOIN tramitacoes t ON t.id_processo = p.id_processo;

-- -----------------------------------------------------------------------------
-- 6. REGRAS NO BANCO (GATILHOS)
-- -----------------------------------------------------------------------------

DELIMITER $$

CREATE TRIGGER trg_afastamento_regras BEFORE INSERT ON afastamentos
FOR EACH ROW
BEGIN
    DECLARE v_id_vinculo INT;
    DECLARE v_cadastro VARCHAR(20);
    DECLARE v_permite_licenca TINYINT;
    DECLARE v_permite_afastamento TINYINT;
    DECLARE v_fixo TINYINT;
    DECLARE v_fim DATE;
    DECLARE v_total INT;

    IF NEW.quantidade_dias IS NULL OR NEW.quantidade_dias < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'a quantidade de dias deve ser maior que zero';
    END IF;

    SELECT s.id_vinculo, s.situacao_cadastro, v.permite_licenca, st.permite_afastamento
      INTO v_id_vinculo, v_cadastro, v_permite_licenca, v_permite_afastamento
      FROM servidores s
      JOIN vinculos v ON v.id_vinculo = s.id_vinculo
      JOIN situacoes_servidores st ON st.id_situacao = s.id_situacao
     WHERE s.id_servidor = NEW.id_servidor;

    IF v_cadastro IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'servidor inexistente';
    END IF;
    IF v_cadastro <> 'VALIDADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN25: servidor com cadastro nao validado nao pode ter licenca';
    END IF;
    IF v_permite_licenca = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'o vinculo do servidor nao permite licenca';
    END IF;
    IF v_permite_afastamento = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'a situacao do servidor nao permite novos afastamentos';
    END IF;

    SELECT prazo_fixo INTO v_fixo FROM tipos_licencas WHERE id_tipo_licenca = NEW.id_tipo_licenca;
    IF v_fixo = 1 THEN
        SELECT COUNT(*) INTO v_total FROM prazos_licencas
         WHERE id_tipo_licenca = NEW.id_tipo_licenca AND id_vinculo = v_id_vinculo AND dias = NEW.quantidade_dias;
        IF v_total = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN06: quantidade de dias nao permitida para este tipo de licenca e vinculo';
        END IF;
    END IF;

    SET v_fim = DATE_ADD(NEW.data_inicio, INTERVAL NEW.quantidade_dias - 1 DAY);
    SELECT COUNT(*) INTO v_total FROM afastamentos a
     WHERE a.id_servidor = NEW.id_servidor
       AND a.status IN ('AGENDADA', 'EM_ANDAMENTO', 'PRORROGADO')
       AND a.data_inicio <= v_fim AND a.data_fim >= NEW.data_inicio
       AND (NEW.id_afastamento_original IS NULL OR a.id_afastamento <> NEW.id_afastamento_original);
    IF v_total > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN10: o servidor ja possui licenca no periodo informado';
    END IF;
END$$

CREATE TRIGGER trg_documento_no_update BEFORE UPDATE ON documentos
FOR EACH ROW
BEGIN
    IF OLD.status = 'ASSINADO' THEN
        IF NOT (NEW.id_processo <=> OLD.id_processo)
           OR NOT (NEW.id_tipo_documento <=> OLD.id_tipo_documento)
           OR NOT (NEW.numero_sequencial_processo <=> OLD.numero_sequencial_processo)
           OR NOT (NEW.numero_documento_oficial <=> OLD.numero_documento_oficial)
           OR NOT (NEW.titulo_ou_nome_arquivo <=> OLD.titulo_ou_nome_arquivo)
           OR NOT (NEW.conteudo_texto <=> OLD.conteudo_texto)
           OR NOT (NEW.caminho_storage <=> OLD.caminho_storage)
           OR NOT (NEW.mime_type <=> OLD.mime_type)
           OR NOT (NEW.tamanho_bytes <=> OLD.tamanho_bytes)
           OR NOT (NEW.hash_sha256 <=> OLD.hash_sha256)
           OR NOT (NEW.status <=> OLD.status)
           OR NOT (NEW.id_documento_corrigido <=> OLD.id_documento_corrigido)
           OR NOT (NEW.id_usuario_upload <=> OLD.id_usuario_upload) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: documento assinado nao pode ser alterado';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_documento_no_delete BEFORE DELETE ON documentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF23: exclusao fisica nao permitida (use status EXCLUIDO)';
END$$

CREATE TRIGGER trg_assinatura_no_update BEFORE UPDATE ON assinaturas_documentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: a assinatura nao pode ser alterada';
END$$

CREATE TRIGGER trg_assinatura_no_delete BEFORE DELETE ON assinaturas_documentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: a assinatura nao pode ser excluida';
END$$

CREATE TRIGGER trg_andamento_no_update BEFORE UPDATE ON andamentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: o andamento nao pode ser alterado';
END$$

CREATE TRIGGER trg_andamento_no_delete BEFORE DELETE ON andamentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: o andamento nao pode ser excluido';
END$$

CREATE TRIGGER trg_tramitacao_no_update BEFORE UPDATE ON tramitacoes
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: a tramitacao nao pode ser alterada';
END$$

CREATE TRIGGER trg_tramitacao_no_delete BEFORE DELETE ON tramitacoes
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RN18: a tramitacao nao pode ser excluida';
END$$

CREATE TRIGGER trg_log_no_update BEFORE UPDATE ON logs_auditoria
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF14: o log de auditoria nao pode ser alterado';
END$$

CREATE TRIGGER trg_log_no_delete BEFORE DELETE ON logs_auditoria
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF14: o log de auditoria nao pode ser excluido';
END$$

CREATE TRIGGER trg_servidor_no_delete BEFORE DELETE ON servidores
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF23: exclusao fisica nao permitida (use a inativacao)';
END$$

CREATE TRIGGER trg_afastamento_no_delete BEFORE DELETE ON afastamentos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF23: exclusao fisica nao permitida (use o status CANCELADO)';
END$$

CREATE TRIGGER trg_processo_no_delete BEFORE DELETE ON processos
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF23: exclusao fisica nao permitida (use o status CANCELADO)';
END$$

DELIMITER ;

-- -----------------------------------------------------------------------------
-- 7. DADOS INICIAIS
-- -----------------------------------------------------------------------------

INSERT INTO parametros (chave, valor, descricao) VALUES
('ALERTA_TERMINO_DIAS', '10', 'RN12: dias de antecedência do alerta de término de licença'),
('SESSAO_INATIVIDADE_MIN', '30', 'RF01: minutos de inatividade até encerrar a sessão'),
('LOGIN_TENTATIVAS_MAX', '5', 'RF01: tentativas erradas antes do bloqueio'),
('LOGIN_BLOQUEIO_MIN', '15', 'RF01: minutos de bloqueio da conta'),
('LINK_VALIDADE_MIN', '30', 'RF02 e RF34: validade do link de uso único'),
('UPLOAD_MAX_BYTES', '15728640', 'RF20: tamanho máximo de arquivo (15 MB)');

INSERT INTO setores (codigo, nome, sigla) VALUES
(100, 'Recursos Humanos', 'RH'),
(200, 'Procuradoria Geral do Município', 'PGM'),
(300, 'Secretaria de Educação', 'SEDUC'),
(400, 'Secretaria de Saúde / Perícia Médica', 'SESA');

INSERT INTO vinculos (nome, permite_licenca) VALUES
('COMISSIONADO', 1),
('CONTR. TEMPORARIO', 1),
('ESTAT.CONCURSADO', 1),
('ESTATUTARIO', 1),
('PENSAO ALIMENTICIA', 0),
('PENSIONISTA', 0),
('SERVIDOR CEDIDO', 1);

INSERT INTO situacoes_servidores (nome, descricao, permite_login, permite_afastamento) VALUES
('ATIVO', 'Servidor em pleno exercício das suas funções', 1, 1),
('INATIVO', 'Servidor inativo (aposentado, desligado ou suspenso)', 0, 0);

INSERT INTO tipos_processos (nome, descricao)
VALUES ('Requerimento', 'Requerimentos administrativos dos servidores');
SET @id_requerimento = LAST_INSERT_ID();

INSERT INTO tipos_processos_setores_conclusao (id_tipo_processo, id_setor)
SELECT @id_requerimento, id_setor FROM setores WHERE sigla = 'RH';

INSERT INTO catalogos_assuntos (id_tipo_processo, descricao, prazo_dias_padrao) VALUES
(@id_requerimento, 'ADICIONAL DE INSALUBRIDADE OU PERICULOSIDADE', 15),
(@id_requerimento, 'ADICIONAL NOTURNO', 15),
(@id_requerimento, 'AFASTAMENTO PARA ESTUDO', 15),
(@id_requerimento, 'AFASTAMENTO PARA MANDATO ELETIVO', 15),
(@id_requerimento, 'AFASTAMENTO PARA CAPACITAÇÃO PROFISSIONAL', 15),
(@id_requerimento, 'AJUDA DE CUSTO/DIÁRIAS/INDENIZAÇÕES DE TRANSPORTE', 15),
(@id_requerimento, 'AUSÊNCIA DO SERVIÇO', 15),
(@id_requerimento, 'CESSÃO PARA OUTRO ÓRGÃO', 15),
(@id_requerimento, 'CÔMPUTO DE TEMPO DE SERVIÇO', 15),
(@id_requerimento, 'EXONERAÇÃO/DEMISSÃO', 15),
(@id_requerimento, 'FÉRIAS NÃO GOZADAS', 15),
(@id_requerimento, 'GRATIFICAÇÃO DE DIFÍCIL ACESSO', 15),
(@id_requerimento, 'HORAS EXTRAS', 15),
(@id_requerimento, 'INCLUSÃO DE DEPENDENTES', 15),
(@id_requerimento, 'LICENÇAS', 15),
(@id_requerimento, 'AFASTAMENTO DE CÔNJUGE', 15),
(@id_requerimento, 'ATIVIDADE POLÍTICA', 15),
(@id_requerimento, 'DOENÇA EM PESSOA DA FAMÍLIA', 15),
(@id_requerimento, 'GESTANTE/PATERNIDADE', 15),
(@id_requerimento, 'INTERESSES PARTICULARES (NÃO REMUNERADA)', 15),
(@id_requerimento, 'PAGAMENTO DE EXERCÍCIOS ANTERIORES', 15),
(@id_requerimento, 'PROGRESSÃO POR MERECIMENTO/HORIZONTAL', 15),
(@id_requerimento, 'PROMOÇÃO/EVOLUÇÃO PELA VIA ACADÊMICA', 15),
(@id_requerimento, 'READAPTAÇÃO', 15),
(@id_requerimento, 'REDUÇÃO DE CARGA HORÁRIA', 15),
(@id_requerimento, 'REMOÇÃO A PEDIDO', 15),
(@id_requerimento, 'VACÂNCIA', 15),
(@id_requerimento, 'OUTROS', 15),
(@id_requerimento, 'AFASTAMENTO POR MOTIVO DE SAÚDE', 15);

INSERT INTO tipos_documentos (nome, gera_numeracao_oficial, sigla_documento, nivel_acesso_padrao) VALUES
('Formulário Padrão de Requerimento', 0, NULL, 'PUBLICO'),
('Anexo', 0, NULL, 'PUBLICO'),
('Parecer', 1, 'PARECER', 'PUBLICO'),
('Exame Médico Pericial (Laudo)', 1, 'LAUDO', 'PRIVADO'),
('Despacho', 1, 'DESPACHO', 'PUBLICO');

INSERT INTO vantagens (nome_vantagem, descricao) VALUES
('Adicional de Insalubridade', 'Devido pelo exercício habitual em local insalubre'),
('Adicional de Periculosidade', 'Devido pelo exercício habitual em condições perigosas'),
('Adicional Noturno', 'Devido pelo serviço noturno prestado'),
('Ajuda de Custo', 'Paga a quem trabalha presencialmente'),
('Auxílio Transporte', 'Despesas de transporte para o trabalho presencial');

INSERT INTO tipos_licencas (nome, prazo_fixo, suspende_vantagens) VALUES
('Licença para tratamento de saúde', 0, 1),
('Licença-maternidade', 1, 0);

INSERT INTO prazos_licencas (id_tipo_licenca, id_vinculo, dias, descricao_opcao)
SELECT t.id_tipo_licenca, v.id_vinculo, x.dias, CONCAT(x.dias, ' dias')
  FROM tipos_licencas t
  JOIN (SELECT 'ESTAT.CONCURSADO' AS nome, 180 AS dias
        UNION ALL SELECT 'ESTATUTARIO', 180
        UNION ALL SELECT 'COMISSIONADO', 120
        UNION ALL SELECT 'CONTR. TEMPORARIO', 120) x
  JOIN vinculos v ON v.nome = x.nome
 WHERE t.nome = 'Licença-maternidade';