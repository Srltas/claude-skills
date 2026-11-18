"""Figures of the example explainer (CBRD-28170, PARAMETER_INFO), drawn with svgfig.

    python3 make_figs.py [out-dir]     # default: img/ next to this script

A note's own script imports svgfig from ~/.claude/skills/worklog/assets instead of the
relative path used here. The bytes below were captured with tcp_log_proxy.py.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "assets"))
from svgfig import MUTED, Figure, B, M, S  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "img")

# The request and the response: header boxes, then one box per repeated unit, grouped by a bracket
fig = Figure(782, 300, "PARAMETER_INFO 요청과 응답",
             "요청과 응답 머리는 그대로이고, 응답 머리 뒤에 바인드 파라미터마다 한 묶음이 온다.")
fig.text(24, 36, "요청: 바뀌지 않음", 14, "bold")
for i, (name, size, hexes) in enumerate([("길이", "4바이트", "00 00 00 09"), ("CAS_INFO", "4바이트", "01 ff ff 03"),
                                         ("함수 번호", "1바이트, 27", "1b"), ("인자 크기", "4바이트, 값 4", "00 00 00 04"),
                                         ("핸들 번호", "4바이트", "00 00 00 01")]):
    fig.box(24 + i * 128, 48, 120, 72, "gray", [B(name), S(size), M(hexes)])
fig.text(24, 162, "응답: 머리는 그대로, 그 뒤에 바인드 파라미터마다 한 묶음 (예: CALL p_pinfo(?, ?, ?, ?))", 14, "bold")
for i, (name, size, hexes) in enumerate([("길이", "4바이트", "00 00 00 4b"), ("CAS_INFO", "4바이트", "01 ff ff 03"),
                                         ("결과 코드", "4바이트, 개수 4", "00 00 00 04")]):
    fig.box(24 + i * 128, 174, 120, 72, "gray", [B(name), S(size), M(hexes)])
for i, param in enumerate(["Num", "Total", "Acc", "Note"]):
    fig.box(420 + i * 86, 174, 80, 72, "blue", [B("묶음 %d" % (i + 1)), S(param)])
fig.bracket(420, 758, 254, "green", "결과 코드만큼 반복. 이번에 모양이 바뀌는 곳")
fig.save(os.path.join(OUT, "parameter-info-request-response.svg"))

# One unit before and after: the same fields in two rows, the new fields only in the second
fig = Figure(822, 270, "바인드 파라미터 묶음 하나",
             "V12 이하 클라이언트는 9바이트 묶음, V13 이상 클라이언트는 그 뒤에 이름 길이와 이름이 붙는다.")
fields = [(150, 80, "모드", "1바이트", "coral"), (236, 104, "데이터 타입", "2바이트", "coral"),
          (346, 88, "scale", "2바이트", "gray"), (440, 104, "precision", "4바이트", "gray")]
for label, y in [("V12 이하", 34), ("V13 이상", 128)]:
    fig.text(24, y + 30, label, 15, "bold")
    fig.text(24, y + 50, "클라이언트", 13, color=MUTED)
    for x, w, name, size, color in fields:
        fig.box(x, y, w, 62, color, [B(name), S(size)])
fig.text(562, 70, "9바이트, 크기 고정", 13, color=MUTED)
fig.box(550, 128, 110, 62, "green", [B("이름 길이"), S("4바이트")])
fig.box(666, 128, 136, 62, "green", [B("이름 + NUL"), S("가변")])
fig.text(150, 214, "9바이트 + 4바이트 + 이름(NUL 포함). 이름이 없으면 길이 1과 NUL 한 바이트", 13, color=MUTED, limit=650)
fig.legend(248, [(150, "coral", "CALL 문은 값만 바로잡힘"), (346, "gray", "그대로"), (446, "green", "V13 이상에만 추가")])
fig.save(os.path.join(OUT, "parameter-info-bundle.svg"))

# Captured bytes: the header, then one row per unit on a shared column grid, a meaning column
COLUMNS = [(118, 50, "모드", "coral"), (174, 78, "데이터 타입", "coral"), (258, 78, "scale", "gray"),
           (342, 120, "precision", "gray"), (468, 120, "이름 길이", "green"), (594, 176, "이름 + NUL", "green")]
NOTE_X = 786


def byte_figure(path, svg_title, desc, title, header, rows, old_row, footnotes, width=1000):
    fig = Figure(width, 0, svg_title, desc)
    fig.text(24, 34, title, 15, "bold")
    for i, (hexes, caption) in enumerate(header):
        x = 118 + i * 140
        fig.box(x, 50, 134, 34, "gray", [M(hexes)])
        fig.text(x + 67, 102, caption, 12, anchor="middle", color=MUTED, limit=150)
    fig.text(24, 72, "머리", 13, "bold")
    fig.column_heads(132, COLUMNS)
    fig.text(NOTE_X, 132, "뜻", 12, "bold", color=MUTED)
    y = 142
    for label, cells, note in rows:
        fig.field_row(y, label, COLUMNS, cells)
        fig.text(NOTE_X, y + 23, note, 13, limit=width - NOTE_X - 16)
        y += 46
    if old_row:
        label, cells, note = old_row
        fig.text(24, y + 20, "같은 문장을 V12 클라이언트(11.4 CCI)가 받으면: 40바이트, 이름 칸 없음", 13, "bold", color=MUTED)
        y += 32
        fig.field_row(y, label, COLUMNS, cells)
        fig.text(468, y + 23, note, 13, color=MUTED, limit=300)
        y += 46
    y += 14
    for line in footnotes:
        fig.text(24, y, line, 12.5, color=MUTED, limit=width - 48)
        y += 20
    fig.height = y + 6
    fig.save(path)


byte_figure(
    os.path.join(OUT, "parameter-info-bytes-call.svg"),
    "CALL p_pinfo(?, ?, ?, ?)의 PARAMETER_INFO 응답 바이트",
    "V13 클라이언트가 받은 75바이트 응답을 묶음별로 나눈 것과, 같은 문장을 V12 클라이언트가 받은 묶음.",
    "CALL p_pinfo(?, ?, ?, ?)의 응답, V13 클라이언트 (75바이트)",
    [("00 00 00 4b", "길이 75"), ("01 ff ff 03", "CAS_INFO"), ("00 00 00 04", "결과 코드: 4개")],
    [("묶음 1", ["01", "80 08", "00 00", "00 00 00 00", "00 00 00 04", "4e 75 6d 00"], "IN · INT(8) · Num"),
     ("묶음 2", ["02", "80 07", "00 00", "00 00 00 00", "00 00 00 06", "54 6f 74 61 6c 00"], "OUT · NUMERIC(7) · Total"),
     ("묶음 3", ["03", "80 15", "00 00", "00 00 00 00", "00 00 00 04", "41 63 63 00"], "INOUT · BIGINT(21) · Acc"),
     ("묶음 4", ["01", "80 02", "00 00", "00 00 00 00", "00 00 00 05", "4e 6f 74 65 00"], "IN · VARCHAR(2) · Note")],
    ("묶음 1", ["01", "80 08", "00 00", "00 00 00 00"], "9바이트에서 끝나고 바로 묶음 2"),
    ["데이터 타입 2바이트: 첫 바이트 0x80은 2바이트 형식 표시(V7부터), 둘째 바이트는 데이터 타입 번호(CCI_U_TYPE, 0x15 = 21).",
     "모드: 1 IN, 2 OUT, 3 INOUT. 저장 프로시저 매개변수에는 크기를 선언할 수 없어 CALL 문의 scale·precision은 0이다."])

byte_figure(
    os.path.join(OUT, "parameter-info-bytes-function.svg"),
    "?= CALL f_pinfo(?)의 PARAMETER_INFO 응답 바이트",
    "V13 클라이언트가 받은 33바이트 응답. 반환값 묶음의 이름은 비어 있다.",
    "?= CALL f_pinfo(?)의 응답, V13 클라이언트 (33바이트)",
    [("00 00 00 21", "길이 33"), ("01 ff ff 03", "CAS_INFO"), ("00 00 00 02", "결과 코드: 2개")],
    [("묶음 1", ["02", "80 02", "00 00", "00 00 00 00", "00 00 00 01", "00"], "OUT · VARCHAR(2) · 반환값"),
     ("묶음 2", ["01", "80 08", "00 00", "00 00 00 00", "00 00 00 02", "61 00"], "IN · INT(8) · a")],
    None,
    ["f_pinfo(a INT) RETURN VARCHAR. 첫 번째 바인드 파라미터(?=)는 반환값이라 매개변수 이름이 없어서 길이 1과 NUL만 온다."])

# Values before and after: a header row of what each slot is, then a red row (before) and a green row (after)
fig = Figure(900, 462, "CALL 문의 PARAMETER_INFO 값, 변경 전과 후",
             "변경 전에는 모든 바인드 파라미터가 IN, 데이터 타입 모름이고 ?= 문장은 한 칸씩 밀렸다. 변경 뒤에는 선언대로 나온다.")
fig.text(24, 34, "CALL p_pinfo(?, ?, ?, ?)", 15, "bold", mono=True)
for i, (slot, declared) in enumerate([("바인드 파라미터 1", "Num IN INT"), ("바인드 파라미터 2", "Total OUT NUMERIC"),
                                      ("바인드 파라미터 3", "Acc INOUT BIGINT"), ("바인드 파라미터 4", "Note IN VARCHAR")]):
    fig.box(130 + i * 188, 48, 180, 48, "white", [B(slot), S(declared)])
fig.text(24, 128, "변경 전", 14, "bold")
fig.text(24, 176, "변경 후", 14, "bold")
for i, after in enumerate(["IN · INT", "OUT · NUMERIC", "INOUT · BIGINT", "IN · VARCHAR"]):
    fig.box(130 + i * 188, 104, 180, 38, "red", [B("IN · 모름")])
    fig.box(130 + i * 188, 152, 180, 38, "green", [B(after)])
fig.text(24, 236, "?= CALL f_pinfo(?)", 15, "bold", mono=True)
for i, (slot, declared) in enumerate([("바인드 파라미터 1 (?=)", "반환값 VARCHAR"), ("바인드 파라미터 2", "a IN INT")]):
    fig.box(130 + i * 280, 250, 272, 48, "white", [B(slot), S(declared)])
fig.text(24, 330, "변경 전", 14, "bold")
fig.text(24, 378, "변경 후", 14, "bold")
fig.box(130, 306, 272, 38, "red", [B("IN · 모름 (인자의 정보)")])
fig.box(410, 306, 272, 38, "red", [B("모드 0")])
fig.text(698, 322, "한 칸씩 밀림:", 13, "bold", color="#cf222e", limit=190)
fig.text(698, 340, "인자의 정보가 첫 칸에 옴", 13, color="#cf222e", limit=190)
fig.box(130, 354, 272, 38, "green", [B("OUT · VARCHAR")])
fig.box(410, 354, 272, 38, "green", [B("IN · INT")])
fig.text(24, 424, "칸 안의 값은 모드 · 데이터 타입. 변경 전 값은 CCI cci_get_param_info로 잰 값이다.", 12.5, color=MUTED)
fig.text(24, 444, "CCI_PREPARE_CALL로 준비한 CALL 문에만, 클라이언트 버전과 상관없이 적용된다.", 12.5, color=MUTED)
fig.save(os.path.join(OUT, "parameter-info-values.svg"))

# Version matrix: client rows by server columns, the result in each cell, a warning below
fig = Figure(872, 404, "클라이언트와 서버의 프로토콜 버전 조합",
             "V13 클라이언트와 V13 서버가 만날 때만 이름이 오간다. 나머지 조합은 이름 칸이 없는 9바이트 묶음이다.")
fig.text(24, 34, "클라이언트와 서버의 프로토콜 버전 조합", 15, "bold")
fig.box(208, 48, 316, 48, "white", [B("서버: 11.4"), S("V12")])
fig.box(532, 48, 316, 48, "white", [B("서버: 새 엔진"), S("V13, CBRD-28170 포함")])
fig.box(24, 104, 176, 104, "white", [B("클라이언트"), S("11.4 CCI 등"), S("V12 이하")])
fig.box(24, 216, 176, 104, "white", [B("클라이언트"), S("새 CCI, 새 JDBC"), S("V13")])
fig.box(208, 104, 316, 104, "gray", [B("지금과 같음"), S("9바이트 묶음")])
fig.box(532, 104, 316, 104, "coral", [B("9바이트 묶음 그대로"), S("CALL 문 값만 바로잡힘")])
fig.box(208, 216, 316, 104, "gray", [B("이름 칸 없음 (서버가 V12)"), S("클라이언트도 이름을 읽지 않음"),
                                     S("cci_get_param_name: -20099"), S("JDBC 이름 기반 메서드: 미지원 예외")])
fig.box(532, 216, 316, 104, "green", [B("묶음마다 매개변수 이름"), S("cci_get_param_name 동작"), S("JDBC 이름 기반 메서드 동작")])
fig.box(24, 334, 824, 52, "red",
        [("주의: V13 서버가 이름 칸 없이 출시되면 새 클라이언트가 응답을 잘못 읽는다 (새 CCI는 PARAMETER_INFO가 모두 -20004).", 12.5, "normal", False),
         ("그래서 이 변경은 PROTOCOL_V13을 처음 출시하는 릴리스에 함께 들어가야 한다.", 12.5, "normal", False)])
fig.save(os.path.join(OUT, "parameter-info-versions.svg"))

Figure.report()
