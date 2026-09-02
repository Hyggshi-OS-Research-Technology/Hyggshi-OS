# HCL (Hyggshi Configuration Language) v1.0 — tóm tắt spec

`iso-config/config/config.ini` không phải INI thuần — nó có dependency
resolution, key-driven dispatch, typed literal và function call. `tools/hcl_parser.py`
implement đúng semantics đó (đã test trực tiếp trên file config.ini thật, xem log chat).

## Type system

| Type       | Ví dụ                                    | Ghi chú |
|------------|-------------------------------------------|---------|
| BOOLEAN    | `Debian = true`                           | |
| STRING     | `codename = "Verdant Valley"`             | luôn có `"..."` |
| NUMBER     | (chưa dùng trong file hiện tại)           | số trần không quote |
| VERSION    | `Version = 1.4.0`                         | dạng `\d+(\.\d+){1,3}` |
| SIZE       | `swap = false` / `1GB` / `custom > 7.2GB` | chỉ áp dụng cho key khai trong `SIZE_KEYS` (hiện tại: `swap`) |
| ENUM       | `desktop = Cinnamon`, `action = run`      | bare identifier không trùng tên section nào |
| REFERENCE  | `base = ${Base}`                          | `${X}` luôn dereference |
| FUNCTION   | `fileinstall(...)`, `command(...)`        | tên phải nằm trong `FUNCTION_NAMES` |
| SECTION    | `[Base]`, `[kernel.Desktop]`              | dấu `.` = subsection |
| COMMENT    | `; ...`                                   | dòng riêng hoặc cuối dòng |

## Reference resolution rules (đã cài trong `Resolver`)

1. `${Name}` hoặc bare `Name` trùng **tên 1 section**:
   - nếu section đó toàn key BOOLEAN → resolve thành key đang `true` (ENUM
     exclusivity — báo lỗi nếu 0 hoặc >1 true). Vd `${Base}` → `"Debian"`.
   - nếu không → trả nguyên section dưới dạng object đã resolve từng field.
     Vd `${config-setup-postpartum-care}`.
2. Bare identifier **không trùng tên section nào** → giữ nguyên là ENUM
   literal, không tự động dò từng key rải rác ở section khác. (Đây là bug
   thật đã bắt được lúc test: `desktop = Cinnamon` từng bị deref nhầm
   thành `true` vì trùng tên key `Cinnamon` trong `[Desktop-Environment]`.)
3. Key tên `kernel` là **key-driven dispatch** riêng: giá trị string của nó
   (`"Desktop"`) được dùng để tìm section `[kernel.Desktop]`, không qua
   quy tắc (1)/(2).
4. Key tên `firmware` cũng key-driven dispatch riêng: giá trị trỏ tới 1 key
   trong `[firmware]`, rồi map `base` đã resolve → section `[firmware-<Base>]`
   tương ứng để lọc gói nào `= true`.

## Validation (chạy trước khi resolve, quét TOÀN BỘ file)

`Resolver.validate_every_entry()` gọi `classify()` trên **mọi** `key = value`
ở **mọi** section — kể cả những key không nằm trên đường mà `resolve_all()`
đi qua. Bắt được:
- `SIZE` sai grammar (không phải `false` / `<n>GB|MB` / `custom > <n>GB|MB`)
- gọi `function(...)` với tên không nằm trong `{fileinstall, filecustom,
  command, make, call}`
- `${ref}` / bare-reference không trỏ tới đâu cả
- `[Base]` hoặc `[Desktop-Environment]` có 0 hoặc >1 giá trị `true` (phải
  đúng 1 — đây là enum, không phải multi-select)
- path trong `fileinstall()/filecustom()/make()/command(file=...)` không
  tồn tại trên đĩa (check bằng `--root`)
- `kernel = "X"` mà không có section `[kernel.X]`
- `desktop = X` trong `[kernel.*]` không khớp key nào trong
  `[Desktop-Environment]`, hoặc khớp nhưng key đó đang `false`

Chạy `--strict` để bất kỳ error nào cũng làm script `exit(1)` — dùng đúng
việc này trong CI để build fail sớm ở bước validate, thay vì fail giữa
chừng lúc debootstrap/mksquashfs (tốn 15-20 phút rồi mới biết config sai).

## Dùng ngoài CLI

```bash
python3 tools/hcl_parser.py iso-config/config/config.ini \
  --root . \
  --emit-json /tmp/resolved.json \
  --emit-env "$GITHUB_ENV" \
  --strict
```


Biến xuất ra `$GITHUB_ENV` bao gồm:
- `HCL_BASE_DISTRO`, `HCL_DESKTOP_ENV`, `HCL_SWAP_MB`
- `HCL_FIRMWARE_PACKAGES`, `HCL_DESKTOP_PACKAGES`
- `HCL_APP_INSTALLS`: danh sách tất cả file và URL app khai báo qua `fileinstall(...)` (ví dụ `./app-for-hyggshi/nexfetch...` hoặc `https://.../app.deb`)
- `HCL_PACKAGES`: danh sách tất cả các gói hệ thống được bật `= true` trong `[package]` (được tự động chuyển tiếp vào `EXTRA_PACKAGES` cho `desktop.sh`)
- `HCL_WELCOME_SCRIPT`: script wizard chào mừng `command(file=...)`

## Step YAML để nối vào `.github/workflows/Build-Hyggshi-OS-ISO.yml`

Chèn ngay sau bước `Checkout repo`, trước mọi bước dùng `$BASE_DISTRO`:

```yaml
      - name: Validate & resolve config.ini (HCL)
        run: |
          python3 tools/hcl_parser.py iso-config/config/config.ini \
            --root "$GITHUB_WORKSPACE" \
            --emit-json /tmp/hcl-resolved.json \
            --emit-env "$GITHUB_ENV" \
            --strict

      - name: Upload resolved config (debug)
        uses: actions/upload-artifact@v4
        with:
          name: hcl-resolved-config
          path: /tmp/hcl-resolved.json
```

Không cần cài thêm gì — script chỉ dùng Python stdlib, runner
`ubuntu-latest` đã có sẵn `python3`.

## Giới hạn hiện tại (thành thật, chưa fix)

- `[package]` group được nhận diện bằng **comment 3 dòng**
  (`;=====` / `; Label` / `;=====`) ngay phía trên — nếu comment format
  đổi (thiếu 1 dòng `====`, hoặc gộp nhiều dòng label) thì package đó rơi
  vào group `(ungrouped)` và sẽ KHÔNG xuất hiện trong `HCL_DESKTOP_PACKAGES`
  dù `key = true`. Đây là giới hạn do dùng comment làm cấu trúc thay vì có
  1 key kiểu `group = "cinnamon"` tường minh — nếu muốn hết rủi ro này,
  nên đổi sang khai group tường minh trong tương lai thay vì suy ra từ
  comment.
- SIZE type mới support `swap`; muốn thêm key SIZE khác thì thêm tên vào
  `SIZE_KEYS` trong `hcl_parser.py`.
- `${X}` struct-resolution (rule 1, nhánh "không phải boolean") mới chỉ
  dùng cho `config = ${config-setup-postpartum-care}`; nếu sau này có
  reference kiểu đó lồng nhiều tầng (struct chứa struct), code hiện tại
  vẫn đệ quy đúng qua `resolve_value()` nhưng CHƯA test case đó.
