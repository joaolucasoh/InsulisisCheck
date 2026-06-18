# Insulísis Check

Insulísis Check é um app iOS criado para ajudar na rotina de cuidado com a Isis, minha cachorra diabética.

O objetivo do projeto é simples: reduzir o risco de esquecer uma aplicação de insulina ou ficar em dúvida se a dose já foi aplicada. A ideia é ter um registro rápido, claro e compartilhado das aplicações, separado por período e por data.

![Isis relaxando enquanto espera o horário da próxima dose](InsulisisCheck/Assets.xcassets/IsisNeutral.imageset/isis-neutral.png)

## Por que este app existe

Cuidar de um pet diabético exige constância. A glicose precisa ser acompanhada, a insulina precisa ser aplicada nos horários certos e, no meio da rotina, é fácil surgir aquela dúvida:

> "Será que eu já apliquei a dose da manhã?"

Este app nasceu para responder essa pergunta rapidamente e dar mais tranquilidade no dia a dia.

## Principais recursos

- Registro das doses da manhã e da noite.
- Controle por data.
- Registro de quem aplicou a insulina.
- Registro manual com horário e quantidade de unidades.
- Atalhos da Siri para marcar uma dose como aplicada.
- Compartilhamento via iCloud/CloudKit para que mais de uma pessoa veja os mesmos registros.
- Widget para acompanhar o status da próxima dose.
- Live Activities para avisar quando uma dose estiver atrasada.
- Cálculo da próxima aplicação com base no intervalo de 12 horas desde a última dose.

## Rotina que o app ajuda a controlar

A Isis recebe insulina a cada 12 horas. Quando uma aplicação é registrada, o app calcula automaticamente o próximo horário esperado.

Se uma dose não for marcada como aplicada no horário previsto, o app pode destacar o atraso, ajudando a evitar esquecimento ou duplicidade.

## Tecnologias

- Swift
- SwiftUI
- App Intents / Siri Shortcuts
- WidgetKit
- ActivityKit / Live Activities
- CloudKit

## Status do projeto

Este é um projeto pessoal, feito para uma necessidade real da nossa rotina familiar. Ele pode evoluir conforme novas necessidades aparecerem no cuidado diário com a Isis.

## Observação

Este app não substitui orientação veterinária. Ele é apenas uma ferramenta de apoio para organização e registro da rotina de cuidado.
