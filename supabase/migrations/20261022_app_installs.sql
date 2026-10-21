-- ══════════════════════════════════════════════════════════════════════════════
-- أجهزة التطبيق وإصداراتها لكل مدرسة — لوحة «الأجهزة» عند المطور
-- ══════════════════════════════════════════════════════════════════════════════
-- تطبيق فلاتر يبلّغ عند كل فتح وبعد كل دخول (lib/data/app_installs.dart): معرّف
-- جهاز عشوائي ثابت، والإصدار ورقم التحديث الصامت، ونوع النسخة، والمنصة. المنشأة
-- والدور من الجلسة لا من الجهاز؛ وقبل الدخول من كود المدرسة داخل نسختها.
-- بلا اسم ولا رقم ولا حساب: الجدول لا يعرف من صاحب الجهاز.
--
-- RLS بلا سياسات: الوصول المباشر مغلق على الجميع. الكتابة عبر report_app_install
-- لصف الجهاز نفسه (معرّفه لا يغادره)، والقراءة عبر app_installs_overview للمطور وحده.
-- جدول سحابي فقط: لا يدخل المزامنة ولا النسخ الاحتياطي.
--
-- آمنة وقابلة لإعادة التنفيذ.

CREATE TABLE IF NOT EXISTS app_installs (
    device_id UUID PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id) ON DELETE SET NULL,
    role VARCHAR(30),
    -- school: نسخة مدرسة من GitHub، general: النسخة العامة، play: Google Play
    channel VARCHAR(10) NOT NULL CHECK (channel IN ('school', 'general', 'play')),
    school_code VARCHAR(50),
    platform VARCHAR(20) NOT NULL,
    version VARCHAR(20) NOT NULL,
    build INTEGER NOT NULL DEFAULT 0,
    patch INTEGER NOT NULL DEFAULT 0,
    first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_installs_tenant ON app_installs(tenant_id);

ALTER TABLE app_installs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_installs FROM anon, authenticated;

-- المنشأة: من الجلسة، وإلا ما عُرف للجهاز من قبل، وإلا مدرسة النسخة.
-- الخروج لا يمحو المدرسة والدور: يبقى الجهاز محسوباً عليها
CREATE OR REPLACE FUNCTION public.report_app_install(
    p_device_id UUID,
    p_channel TEXT,
    p_school_code TEXT,
    p_platform TEXT,
    p_version TEXT,
    p_build INTEGER,
    p_patch INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT := NULLIF(public.app_claim('role'), '');
    v_tenant UUID := public.app_tenant_id();
    v_code TEXT := NULLIF(UPPER(TRIM(COALESCE(p_school_code, ''))), '');
    v_platform TEXT := LOWER(TRIM(COALESCE(p_platform, '')));
    v_version TEXT := TRIM(COALESCE(p_version, ''));
    v_code_tenant UUID;
BEGIN
    IF p_device_id IS NULL
       OR p_channel IS NULL OR p_channel NOT IN ('school', 'general', 'play')
       OR v_version !~ '^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$'
       OR v_platform !~ '^[a-z]{2,20}$' THEN
        RETURN;
    END IF;
    IF v_code IS NOT NULL AND v_code !~ '^[A-Z0-9_-]{1,50}$' THEN
        v_code := NULL;
    END IF;
    IF length(COALESCE(v_role, '')) > 30 THEN
        v_role := LEFT(v_role, 30);
    END IF;
    IF v_tenant IS NULL AND v_code IS NOT NULL THEN
        SELECT t.id INTO v_code_tenant FROM tenants t WHERE UPPER(t.code) = v_code LIMIT 1;
    END IF;

    INSERT INTO app_installs (device_id, tenant_id, role, channel, school_code, platform, version, build, patch)
    VALUES (p_device_id, COALESCE(v_tenant, v_code_tenant), v_role, p_channel, v_code, v_platform, v_version,
            GREATEST(COALESCE(p_build, 0), 0), GREATEST(COALESCE(p_patch, 0), 0))
    ON CONFLICT (device_id) DO UPDATE SET
        tenant_id = COALESCE(v_tenant, app_installs.tenant_id, EXCLUDED.tenant_id),
        role = COALESCE(v_role, app_installs.role),
        channel = EXCLUDED.channel,
        school_code = EXCLUDED.school_code,
        platform = EXCLUDED.platform,
        version = EXCLUDED.version,
        build = EXCLUDED.build,
        patch = EXCLUDED.patch,
        last_seen = NOW();
END $$;

REVOKE ALL ON FUNCTION public.report_app_install(UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) FROM PUBLIC;
-- قبل الدخول أيضاً: الجهاز يُحسب على مدرسة نسخته من أول فتح
GRANT EXECUTE ON FUNCTION public.report_app_install(UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO anon, authenticated;

-- للمطور: كل مدرسة (ولو بلا أجهزة) مع أجهزتها مجمّعة حسب النسخة والمنصة والإصدار،
-- ثم الأجهزة التي لم تُعرف مدرستها مجمّعة حسب كود نسختها
CREATE OR REPLACE FUNCTION public.app_installs_overview()
RETURNS TABLE (
    tenant_id UUID,
    tenant_code TEXT,
    tenant_name TEXT,
    channel TEXT,
    platform TEXT,
    version TEXT,
    patch INTEGER,
    devices BIGINT,
    recent BIGINT,
    last_seen TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_developer() THEN
        RAISE EXCEPTION 'غير مصرح';
    END IF;

    RETURN QUERY
    SELECT t.id, t.code::TEXT, t.name::TEXT,
           i.channel::TEXT, i.platform::TEXT, i.version::TEXT, i.patch,
           COUNT(i.device_id), COUNT(i.device_id) FILTER (WHERE i.last_seen > NOW() - INTERVAL '30 days'),
           MAX(i.last_seen)
    FROM tenants t
    LEFT JOIN app_installs i ON i.tenant_id = t.id
    GROUP BY t.id, t.code, t.name, i.channel, i.platform, i.version, i.patch
    UNION ALL
    SELECT NULL::UUID, i.school_code::TEXT, NULL::TEXT,
           i.channel::TEXT, i.platform::TEXT, i.version::TEXT, i.patch,
           COUNT(*), COUNT(*) FILTER (WHERE i.last_seen > NOW() - INTERVAL '30 days'),
           MAX(i.last_seen)
    FROM app_installs i
    WHERE i.tenant_id IS NULL
    GROUP BY i.school_code, i.channel, i.platform, i.version, i.patch;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.app_installs_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.app_installs_overview() TO authenticated;
