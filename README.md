# DeepESG - Teste Cloud Engineer

Projeto configurado para atender as necessidades do teste proposto. O foco principal é a utilização de IaC com Terraform para o provisionamento de uma infraestrutura para o deploy de uma aplicação na AWS. 

## :mag_right: Escopo da Aplicação
A aplicação consiste em um servidor frontend e um backend. Ela armazena valores que o usuário insere em uma lista e os exibe na tela. Imagens docker foram buildadas para cada um dos servidores. Elas estão armazenadas em repositórios no DockerHub. Os servidores serão gerenciados via Docker Compose dentro da instancia. 

## :whale2: Docker Compose
A aplicação irá ser iniciada via Docker Compose. O container do servidor frontend responde na porta 3000, mas a 8080 da instancia irá ser usada para o acesso do mesmo. Já o container do backend responde na 5500, usando a 80 da instancia  para para o acesso. 

## :rocket: Terraform
O projeto possui 3 arquivos `.tf` para a configuração da infra. O `main.tf` contempla a criação dos seguintes recursos: VPC e seus componentes, um Security Group, um Bucket S3, um RDS PostgreSQL, uma instancia configurada para iniciar a aplicação e um **Application Load Balancer** para o acesso da mesma. No `variables.tf` estão declaradas as variáveis necessárias em alguns recursos. Já o `terraform.tfvars` irá conter os valores das variáveis. 

* Recursos Criados

 **VPC e Subnets**
 
O recurso `aws_vpc`  irá criar uma VPC com 4 subnets: 2 publicas e 2 privadas. A VPC irá possuir o CIDR `128.0.0.0/16` enquanto que as subnets irão possuir CIDRs `/24`. Os recursos `aws_subnet` são responsáveis por criar as subnets. As publicas estão configuradas para atribuir um IP publico na instancia. Um Internet Gateway(`aws_internet_gateway`), Route Table(`aws_route_table`) e Route Table Associations(`aws_route_table_association`) foram configurados nas subnets publicas para garantir o acesso dos recursos a Internet. Para prevenir o acesso publico aos recursos, o `aws_security_group` irá criar um Security Group configurado para permitir o acesso da maquina local e de requisições provenientes da VPC.

 **Load Balancer**

Para podermos acessar a aplicação, iremos criar um Application Load Balancer com o recurso `aws_lb`. Ele está configurado com o Security Group criado junto a VPC e associado com as subnets publicas. O listener (`aws_lb_listener`) está configurado com o protocolo HTTP na porta 80. Ele irá fazer um forwarding para um Target Group. O recurso `aws_lb_target_group` está usando o protocolo HTTP e apontando para a porta 8080. Essa é a porta configurada no compose que a aplicação responde. Já o `aws_lb_target_group_attachment` está configurado para associar a instancia criada ao Target Group liberando a porta 8080. O parametro `output` irá disponibilizar o DNS do Load Balancer.

**Instancia EC2**

O recurso `aws_instance` irá provisionar uma instancia para o deploy da aplicação. Ela está configurada com uma subnet publica e o security group criado com a VPC. Para preparar a instancia pro deploy algumas dependências precisam ser instaladas durante a inicialização. Um script(install-deps) foi criado para instalar o **Docker** e o **Docker Compose**. Uma `connection` SSH foi configurada, ela irá usar a chave privada gerada pelo usuário. Um `provisioner` irá transferir esse script para dentro da instancia. Outro `provisioner` é responsável por copiar o **docker-compose.yml**. O `remote-exec` irá usar a conexão SSH criada para mudar a permissão do script, executá-lo e iniciar o deploy da aplicação via **docker-compose**. 

**RDS PostgreSQL**

Para garantir o armazenamento o armazenamento dos dados, um banco de dados RDS é necessário. O recurso `aws_db_instance` ira prover este banco. Os dados de acesso irão ser configurados através das variáveis contidas no `variables.tf`. O recurso `aws_db_subnet_group` é usado para associar o banco a subnets. No caso as subnets publicas irão ser usadas. 


* Variáveis

Os arquivos `variables.tf` e `terraform.tfvars` são usados para armazenar e prover variáveis de ambiente que o `main.tf`precisa para funcionar. Elas tornam algumas configurações mais fáceis, assim como são uma maneira melhor para usar dados sensíveis, como keys no terraform. O `variables.tf` irá declarar as variáveis que iremos usar. Elas são:
   * AWS_ACCESS_KEY - Access Key do usuário criado da AWS;
   * AWS_SECRET_KEY - Secret Key do usuário criado na AWS;
   * AWS_REGION - Região da AWS onde a infra será criada;
   * PRIVATE_KEY_PATH - Local da chave privada;
   * PUBLIC_KEY - Conteúdo da chave publica;
   * DB_PASS - Senha para acesso ao banco;
   * DB_NAME - Nome do banco a ser criado;
   * DB_USER - Usuário master do banco a ser criado

Elas são declaradas da seguinte maneira:
```bash
variable "NOME_DA_ENV" {}
```
Ja o `terraform.tfvars` irá conter os valores das variáveis. Eles são declarados da seguinte maneira:
```bash
NOME_DA_ENV = "valor-da-env"
```

## :bookmark_tabs: Instruções de Uso

1 - Clone este repositório; 

2 - [Instale](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) o Terraform em sua maquina. Para verificar a instalação, execute o comando:
```bash
terraform version
```

3 - Em sua conta AWS, crie um usuário no IAM com permissão de Admin. Depois crie uma Access Key com acesso ao CLI. Faça o download do arquivo contendo as keys do usuário. [Documentação do IAM](https://docs.aws.amazon.com/pt_br/IAM/latest/UserGuide/id_users_create.html);

4 - Na raiz do projeto, crie um par de chaves SSH. Elas irão ser usadas para a configuração da instancia EC2; 
```bash
ssh-keygen -t rsa -b 4096 -f nome-da-key
```
5 - No arquivo `main.tf`, vá até o recurso `aws_security_group`. Mude o parâmetro `cidr_blocks` do primeiro `ingress` para o IP de sua maquina. Você pode consultar seu IP nesse [site](https://www.whatismyip.com/).
```bash
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["IP.DA.SUA.MAQUINA/32"]
  }
```

5 - Configure o valor das variáveis no arquivo `terraform.tfvars. 
```bash
AWS_ACCESS_KEY = "access-key"
AWS_SECRET_KEY = "secret-key"
AWS_REGION = "sa-east-1"
PRIVATE_KEY_PATH = "nome-da-chave-privada"
PUBLIC_KEY = "ssh-rsa AAAA..."
DB_PASS = "senha-do-banco"
DB_NAME = "postgres"
DB_USER = "postgres"
```

6 - Feito isso, podemos aplicar a infraestrutura na AWS. Para verificar os recursos a serem criados, use o comando: 
```bash
terraform plan
```
Para aplicar os recursos use:
```bash
terraform apply
```


7 - Ao final do processo, o DNS do Load Balancer para acessar a aplicação estará disponível:
```bash
alb_dns_name = "deepesg-lb-abcde13245.sa-east-1.elb.amazonaws.com"
```

8 - Acesse o DNS em um navegador de sua preferencia.


9 - Para apagar os recursos da infraestrutura, use o comando:
```bash
terraform destroy
```


